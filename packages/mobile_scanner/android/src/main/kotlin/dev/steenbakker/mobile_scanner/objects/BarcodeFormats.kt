package dev.steenbakker.mobile_scanner.objects

enum class BarcodeFormats(val intValue: Int) {
    UNKNOWN(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UNKNOWN),
    ALL_FORMATS(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_ALL_FORMATS),
    CODE_128(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_CODE_128),
    CODE_39(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_CODE_39),
    CODE_93(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_CODE_93),
    CODABAR(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_CODABAR),
    DATA_MATRIX(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_DATA_MATRIX),
    EAN_13(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_13),
    EAN_8(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_EAN_8),
    ITF(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_ITF),
    QR_CODE(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_QR_CODE),
    UPC_A(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_A),
    UPC_E(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_UPC_E),
    PDF417(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_PDF417),
    AZTEC(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_AZTEC),

    // 自定义 ISLI 图标码格式。
    // 不属于 MLKit 支持范围，由项目内置的 ISLIDecoderHandler/native 解码器产出。
    // 选用 8192 (= 2 << 12)，避开 MLKit 现有的 1..4096 位图取值。
    // 注意：enum 常量在 companion object 之前求值，所以这里不能引用 ISLI_FORMAT，必须直接写字面量。
    ISLI(8192),

    // 自定义 ISLI 线性码（1D）格式。
    // 由项目内置的 ISLILineDecoderHandler/native 解码器产出。
    // 选用 16384 (= 2 << 13)，避开 MLKit 与 ISLI(8192)。
    ISLI_LINE(16384);

    companion object {
        const val ISLI_FORMAT: Int = 8192
        const val ISLI_LINE_FORMAT: Int = 16384

        fun fromRawValue(rawValue: Int): BarcodeFormats {
            return when(rawValue) {
                -1 -> UNKNOWN
                0 -> ALL_FORMATS
                1 -> CODE_128
                2 -> CODE_39
                4 -> CODE_93
                8 -> CODABAR
                16 -> DATA_MATRIX
                32 -> EAN_13
                64 -> EAN_8
                128 -> ITF
                256 -> QR_CODE
                512 -> UPC_A
                1024 -> UPC_E
                2048 -> PDF417
                4096 -> AZTEC
                ISLI_FORMAT -> ISLI
                ISLI_LINE_FORMAT -> ISLI_LINE
                else -> UNKNOWN
            }
        }
    }
}