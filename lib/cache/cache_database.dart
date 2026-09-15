import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'cache_blob.dart';
import 'cache_paths.dart';
import 'cache_record.dart';

/// 缓存数据库（sqflite，App 私有目录 ApplicationSupportDirectory/cache.db）
///
/// 两张表，按用途分层：
/// - `cache_blobs`：**文件本体索引，账号无关**。同一资源在所有账号间共用一份文件，
///   key 只由资源 ID（或 URL 哈希）决定，落盘位置为 cache_resources/{key}
/// - `cache_records`：**账号维度元数据**。权限校验结果、离线状态、访问记录、
///   展示信息都带 accountId，通过 blobKey 引用文件本体
///
/// 这样切换账号只重建元数据，命中已有文件本体即可直接复用、无需重新下载。
class CacheDatabase {
  static final CacheDatabase _instance = CacheDatabase._internal();
  factory CacheDatabase() => _instance;
  CacheDatabase._internal();

  /// 旧版本（无账号模型）数据的占位账号，首次同步时归属当前账号
  static const String legacyAccountId = '*';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final Directory dir = await getApplicationSupportDirectory();
    final String path = '${dir.path}/cache.db';
    return openDatabase(
      path,
      version: 2,
      onCreate: (Database db, int version) async {
        await _createV1Schema(db);
        await _ensureV2Schema(db);
      },
      onUpgrade: (Database db, int from, int to) async {
        // v1 → v2：拆成「共享文件本体 + 账号元数据」，老数据就地迁移保留
        await _ensureV2Schema(db);
      },
    );
  }

  /// v1 结构：仅 cache_records（含 url/localPath/fileSize，未区分账号）
  Future<void> _createV1Schema(Database db) async {
    await db.execute('''
      CREATE TABLE cache_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resourceId TEXT,
        resourceOldId TEXT,
        resourceName TEXT,
        resourceType INTEGER,
        resourceSuffix TEXT,
        url TEXT,
        localPath TEXT,
        fileSize INTEGER,
        goodsId TEXT,
        goodsName TEXT,
        goodsImage TEXT,
        isliCode TEXT,
        versionCode TEXT,
        resourceIndex INTEGER,
        status INTEGER,
        progress REAL,
        createdAt INTEGER,
        updatedAt INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_cache_goods ON cache_records(goodsId)');
    await db.execute('CREATE INDEX idx_cache_status ON cache_records(status)');
  }

  /// 幂等升级到 v2（onCreate 与 onUpgrade 共用，保证两条路径结构一致）
  Future<void> _ensureV2Schema(Database db) async {
    final Set<String> columns =
        (await db.rawQuery('PRAGMA table_info(cache_records)'))
            .map((Map<String, Object?> c) => c['name']?.toString() ?? '')
            .toSet();

    Future<void> addColumn(String name, String ddl) async {
      if (columns.contains(name)) return;
      await db.execute('ALTER TABLE cache_records ADD COLUMN $name $ddl');
    }

    // 1. 账号维度元数据列（权限 / 离线状态 / 访问记录）
    await addColumn('accountId', 'TEXT');
    await addColumn('blobKey', 'TEXT');
    await addColumn('permission', 'INTEGER DEFAULT 0');
    await addColumn('accessCount', 'INTEGER DEFAULT 0');
    await addColumn('lastAccessAt', 'INTEGER');
    // 老数据归属未知账号，且当时能缓存说明权限已通过
    await db.execute(
        "UPDATE cache_records SET accountId = '$legacyAccountId' WHERE accountId IS NULL");
    await db.execute('UPDATE cache_records SET permission = 1 '
        "WHERE accountId = '$legacyAccountId' AND (permission IS NULL OR permission = 0)");

    // 2. 文件本体表（账号无关）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_blobs (
        key TEXT PRIMARY KEY,
        url TEXT,
        localPath TEXT,
        fileSize INTEGER,
        resourceType INTEGER,
        isHls INTEGER,
        versionCode TEXT,
        createdAt INTEGER,
        updatedAt INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cache_blob_url ON cache_blobs(url)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cache_account ON cache_records(accountId)');

    // 3. 把老记录里的文件本体信息搬到共享层，并回填 blobKey
    final List<Map<String, Object?>> legacy = await db.query(
      'cache_records',
      columns: <String>[
        'id',
        'resourceId',
        'resourceOldId',
        'url',
        'localPath',
        'fileSize',
        'resourceType',
        'versionCode',
        'createdAt',
        'updatedAt',
      ],
      where: "blobKey IS NULL OR blobKey = ''",
    );
    for (final Map<String, Object?> row in legacy) {
      final String url = row['url']?.toString() ?? '';
      final String key = CacheBlob.keyOf(
        resourceId: row['resourceId']?.toString() ?? '',
        resourceOldId: row['resourceOldId']?.toString() ?? '',
        url: url,
      );
      final String? localPath = row['localPath']?.toString();
      final int createdAt =
          (row['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
      if (localPath != null && localPath.isNotEmpty) {
        await db.insert(
          'cache_blobs',
          <String, Object?>{
            'key': key,
            'url': url,
            'localPath': CachePaths.toStored(localPath),
            'fileSize': (row['fileSize'] as int?) ?? 0,
            'resourceType': (row['resourceType'] as int?) ?? 0,
            'isHls': localPath.toLowerCase().endsWith('.m3u8') ? 1 : 0,
            'versionCode': row['versionCode']?.toString(),
            'createdAt': createdAt,
            'updatedAt': (row['updatedAt'] as int?) ?? createdAt,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await db.update(
        'cache_records',
        <String, Object?>{'blobKey': key},
        where: 'id = ?',
        whereArgs: <Object?>[row['id']],
      );
    }
  }

  /// 某账号的全部缓存记录（联表带出共享文件本体信息，按创建时间倒序）
  ///
  /// url/localPath/fileSize 为 blob 派生字段，上层使用方式保持不变。
  Future<List<CacheRecord>> recordsOf(String accountId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT r.id, r.accountId, r.blobKey, r.resourceId, r.resourceOldId,
             r.resourceName, r.resourceType, r.resourceSuffix, r.goodsId,
             r.goodsName, r.goodsImage, r.isliCode, r.versionCode,
             r.resourceIndex, r.status, r.progress, r.permission,
             r.accessCount, r.lastAccessAt, r.createdAt, r.updatedAt,
             b.url AS blobUrl, b.localPath AS blobPath, b.fileSize AS blobSize
      FROM cache_records r
      LEFT JOIN cache_blobs b ON b.key = r.blobKey
      WHERE r.accountId = ?
      ORDER BY r.createdAt DESC
    ''', <Object?>[accountId]);
    return rows
        .map((Map<String, Object?> row) =>
            CacheRecord.fromMap(row.cast<String, dynamic>()))
        .toList();
  }

  /// 全部文件本体（账号无关，所有账号共享）
  Future<List<CacheBlob>> blobs() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows =
        await db.query('cache_blobs', orderBy: 'createdAt DESC');
    return rows
        .map((Map<String, Object?> row) =>
            CacheBlob.fromMap(row.cast<String, dynamic>()))
        .toList();
  }

  /// 写入/更新文件本体索引
  Future<void> upsertBlob(CacheBlob blob) async {
    final Database db = await database;
    await db.insert('cache_blobs', blob.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 删除文件本体索引
  Future<void> deleteBlob(String key) async {
    final Database db = await database;
    await db.delete('cache_blobs', where: 'key = ?', whereArgs: <Object?>[key]);
  }

  /// 引用该文件本体的记录数（**跨账号**统计，用于判断文件能否回收）
  Future<int> refCountOfBlob(String key) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM cache_records WHERE blobKey = ?',
      <Object?>[key],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  /// 把旧版本（无账号归属）的记录归到指定账号
  Future<void> claimLegacyRecords(String accountId) async {
    final Database db = await database;
    await db.update(
      'cache_records',
      <String, Object?>{'accountId': accountId},
      where: 'accountId = ?',
      whereArgs: <Object?>[legacyAccountId],
    );
  }

  /// 插入记录，返回自增 id
  Future<int> insert(CacheRecord record) async {
    final Database db = await database;
    return db.insert('cache_records', record.toMap()..remove('id'));
  }

  /// 更新记录
  Future<void> update(CacheRecord record) async {
    final Database db = await database;
    await db.update(
      'cache_records',
      record.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  /// 删除记录（仅账号元数据；文件本体是否回收由 CacheService 按引用计数决定）
  Future<void> delete(int id) async {
    final Database db = await database;
    await db.delete('cache_records', where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
