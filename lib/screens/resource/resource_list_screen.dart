import 'package:flutter/material.dart';

class ResourceListScreen extends StatefulWidget {
  const ResourceListScreen({Key? key}) : super(key: key);

  @override
  State<ResourceListScreen> createState() => _ResourceListScreenState();
}

class _ResourceListScreenState extends State<ResourceListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('资源列表'),
      ),
      body: const Center(
        child: Text('资源列表页面'),
      ),
    );
  }
}
