import 'package:fmlink/models/publisher_model.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/screens/auth/login_screen.dart';
import 'package:fmlink/screens/discover/discover_screen.dart';
import 'package:fmlink/screens/publish/publish_screen.dart';
import 'package:fmlink/screens/publish/publication_detail_screen.dart';
import 'package:fmlink/screens/publish/publication_desc_screen.dart';
import 'package:fmlink/screens/publish/publisher_detail_screen.dart';
import 'package:fmlink/screens/publish/publication_source_list_screen.dart';
import 'package:fmlink/screens/resource/resource_list_screen.dart';
import 'package:fmlink/screens/resource/resource_play_screen.dart';
import 'package:fmlink/screens/resource/resource_model3d_screen.dart';
import 'package:fmlink/screens/resource/resource_source_detail_screen.dart';
import 'package:fmlink/screens/isli/isli_copyright_screen.dart';
import 'package:fmlink/screens/purchase/purchase_screen.dart';
import 'package:fmlink/screens/history/history_screen.dart';
import 'package:fmlink/screens/history/link_management_screen.dart';
import 'package:fmlink/screens/profile/profile_screen.dart';
import 'package:fmlink/screens/profile/about_screen.dart';
import 'package:fmlink/screens/profile/faq_screen.dart';
import 'package:fmlink/screens/profile/account_security_screen.dart';
import 'package:fmlink/screens/profile/bind_phone_screen.dart';
import 'package:fmlink/screens/profile/set_password_screen.dart';
import 'package:fmlink/screens/profile/device_management_screen.dart';
import 'package:fmlink/screens/profile/delete_account_screen.dart';
import 'package:fmlink/screens/profile/my_like_screen.dart';
import 'package:fmlink/screens/scan/scan_screen.dart';
import 'package:fmlink/screens/scan/scan_result_screen.dart';
import 'package:fmlink/screens/scan/scan_help_screen.dart';
import 'package:fmlink/screens/scan/book_help_screen.dart';
import 'package:fmlink/screens/webview/webview_screen.dart';
import 'package:fmlink/screens/main/main_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MainScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/discover',
        builder: (context, state) => const DiscoverScreen(),
      ),
      GoRoute(
        path: '/publish',
        builder: (context, state) => const PublishScreen(),
      ),
      GoRoute(
        path: '/publication-detail',
        builder: (context, state) {
          final goodsId = state.uri.queryParameters['goodsId'] ?? '';
          return PublicationDetailScreen(goodsId: goodsId);
        },
      ),
      GoRoute(
        path: '/publication-desc',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          final title = data?['title'] ?? '出版物简介';
          final content = data?['content'] ?? '';
          return PublicationDescScreen(title: title, content: content);
        },
      ),
      GoRoute(
        path: '/publisher-detail',
        builder: (context, state) {
          final publisher = state.extra as PublisherModel?;
          return PublisherDetailScreen(publisher: publisher!);
        },
      ),
      GoRoute(
        path: '/publication-source-list',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          return PublicationSourceListScreen(
            goodsId: data?['goodsId'] ?? '',
            goodsName: data?['goodsName'] ?? '',
            goodsImage: data?['goodsImage'] ?? '',
            serviceCode: data?['serviceCode'] ?? '',
            prefixCode: data?['prefixCode'] ?? '',
            versionCode: data?['versionCode'] ?? 1,
            resourceFormats: data?['resourceFormats'] ?? [],
          );
        },
      ),
      GoRoute(
        path: '/resource/list',
        builder: (context, state) {
          final data =
              state.extra as Map<String, dynamic>? ?? <String, dynamic>{};
          return ResourceListScreen(extra: data);
        },
      ),
      GoRoute(
        path: '/resource/play',
        builder: (context, state) {
          final data =
              state.extra as Map<String, dynamic>? ?? <String, dynamic>{};
          return ResourcePlayScreen(extra: data);
        },
      ),
      GoRoute(
        path: '/resource/source-detail',
        builder: (context, state) {
          final data =
              state.extra as Map<String, dynamic>? ?? <String, dynamic>{};
          return ResourceSourceDetailScreen(extra: data);
        },
      ),
      GoRoute(
        path: '/resource/model3d',
        builder: (context, state) {
          final String? url = state.extra as String?;
          return ResourceModel3dScreen(url: url);
        },
      ),
      GoRoute(
        path: '/isli/copyright',
        builder: (context, state) {
          final mprCode = state.uri.queryParameters['mprCode'] ?? '';
          return IsliCopyrightScreen(mprCode: mprCode);
        },
      ),
      GoRoute(
        path: '/purchase',
        builder: (context, state) {
          // 购买页参数与小程序购买页 onLoad options 一致，由入口（源/资源页）以 extra 传入
          final data = state.extra as Map<String, dynamic>? ?? <String, dynamic>{};
          return PurchaseScreen(params: data);
        },
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/link-management',
        builder: (context, state) => const LinkManagementScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const MyScreen(),
      ),
      GoRoute(
        path: '/profile/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/profile/faq',
        builder: (context, state) => const FaqScreen(),
      ),
      GoRoute(
        path: '/profile/account-security',
        builder: (context, state) => const AccountSecurityScreen(),
      ),
      GoRoute(
        path: '/profile/bind-phone',
        builder: (context, state) => const BindPhoneScreen(),
      ),
      GoRoute(
        path: '/profile/set-password',
        builder: (context, state) => const SetPasswordScreenWithExtra(),
      ),
      GoRoute(
        path: '/profile/device-management',
        builder: (context, state) => const DeviceManagementScreen(),
      ),
      GoRoute(
        path: '/profile/delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/profile/my-like',
        builder: (context, state) => const MyLikeScreen(),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/scan/result',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          return ScanResultScreen(
            isliCode: data?['isliCode'] ?? '',
            resultData: data?['data'],
          );
        },
      ),
      GoRoute(
        path: '/scan/help',
        builder: (context, state) => const ScanHelpScreen(),
      ),
      GoRoute(
        path: '/scan/book-help',
        builder: (context, state) => const BookHelpScreen(),
      ),
      GoRoute(
        path: '/webview',
        builder: (context, state) {
          final url = state.uri.queryParameters['url'] ?? '';
          final title = state.uri.queryParameters['title'];
          return WebViewScreen(url: url, title: title);
        },
      ),
    ],
  );
}