import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Button widget for analyze image function
class AnalyzeImageButton extends StatelessWidget {
  /// Construct a new [AnalyzeImageButton] instance.
  const AnalyzeImageButton({
    required this.controller,
    this.scanWindow,
    super.key,
  });

  /// Controller which is used to call analyzeImage
  final MobileScannerController controller;

  /// The scan window rectangle in relative coordinates (0.0 to 1.0).
  ///
  /// When provided, only the portion of the image within this region
  /// will be decoded. If omitted but a scan window was previously set
  /// via [MobileScannerController.updateScanWindow], that window is used.
  final Rect? scanWindow;

  Future<void> _onPressed(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Analyze image is not supported on web'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final picker = ImagePicker();

    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) {
      return;
    }

    final BarcodeCapture? barcodes = await controller.analyzeImage(
      image.path,
      scanWindow: scanWindow,
    );

    if (!context.mounted) {
      return;
    }

    // Use the explicit scanWindow if provided, otherwise check if the controller
    // has an active scan window that will be used automatically.
    final bool hasScanWindow = scanWindow != null || controller.scanWindow != null;
    final String scanWindowLabel =
        hasScanWindow ? ' (scan window cropped)' : '';

    final snackBar =
        barcodes != null && barcodes.barcodes.isNotEmpty
            ? SnackBar(
              content: Text('Barcode found!$scanWindowLabel'),
              backgroundColor: Colors.green,
            )
            : SnackBar(
              content: Text('No barcode found!$scanWindowLabel'),
              backgroundColor: Colors.red,
            );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      color: Colors.white,
      icon: const Icon(Icons.image),
      iconSize: 32,
      onPressed: () => _onPressed(context),
    );
  }
}
