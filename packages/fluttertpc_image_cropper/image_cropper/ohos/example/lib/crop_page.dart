import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:imagecropper_ohos/imagecropper_ohos.dart';
import 'package:image_picker/image_picker.dart';
import 'package:imagecropper_ohos/page/crop.dart';

class CropWidget extends StatefulWidget {
  final String filePath;

  CropWidget({Key? key, required this.filePath}) : super(key: key);

  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<CropWidget> {
  final imageCropper = ImagecropperOhos();
  final cropKey = GlobalKey<CropState>();
  File? _file;
  File? _sample;
  File? _lastCropped;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      imageCropper.sampleImage(
        path: widget.filePath,
        maximumSize: context.size!.longestSide.ceil(),
      ).then((value) {
        setState(() {
          _sample = value!;
          _file = File(widget.filePath);
        });
      });
    });
  }


  @override
  void dispose() {
    super.dispose();
    _sample?.delete();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SafeArea(
        child: Container(
          color: Colors.black,
          child: _sample == null ? _buildOpeningImage() : _buildCroppingImage(),
        ),
      ),
    );
  }

  Widget _buildOpeningImage() {
    return Center(child: _buildOpenImage());
  }

  Widget _buildCroppingImage() {
    return Column(
      children: <Widget>[
        Expanded(
          child: Crop.file(_sample!, key: cropKey,),
        ),
        Container(
          padding: const EdgeInsets.only(top: 20.0),
          alignment: AlignmentDirectional.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              TextButton(
                child: Text(
                  '确认',
                  style: Theme
                      .of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: Colors.white),
                ),
                onPressed: () => _cropImage(),
              ),
            ],
          ),
        )
      ],
    );
  }


  Widget _buildOpenImage() {
    return TextButton(
      child: Text(
        'Open Image',
        style: Theme
            .of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Colors.white),
      ),
      onPressed: () => _openImage(),
    );
  }

  Future<void> _openImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
          source: ImageSource.gallery);
      if (pickedFile == null) return;
      final file = File(pickedFile.path);
      debugPrint('$file');
      final sample = await imageCropper.sampleImage(
        path: pickedFile.path,
        maximumSize: context.size!.longestSide.ceil(),
      );

      _sample?.delete();
      _file?.delete();

      setState(() {
        _sample = sample;
        _file = file;
      });
    } catch (e, s) {
      print(' _openImage $e,$s');
    }
  }

  Future<void> _cropImage() async {
    final scale = cropKey.currentState?.scale;
    final area = cropKey.currentState?.area;
    final angle = cropKey.currentState?.angle;
    final cx = cropKey.currentState?.cx ?? 0;
    final cy = cropKey.currentState?.cy ?? 0;
    if (area == null) {
      // cannot crop, widget is not setup
      return;
    }

    // scale up to use maximum possible number of pixels
    // this will sample image in higher resolution to make cropped image larger
    final sample = await imageCropper.sampleImage(
      path: _file!.path,
      maximumSize: (2000 / scale!).round(),
    );

    final file = await imageCropper.cropImage(
      file: sample!,
      area: area,
      angle: angle,
      cx: cx,
      cy: cy,
    );
    sample.delete();

    _lastCropped?.delete();
    _lastCropped = file;

    Navigator.pop(context, file.path);
  }
}
