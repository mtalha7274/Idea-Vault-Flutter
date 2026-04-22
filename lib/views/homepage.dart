import 'dart:io';

import 'package:flutter/material.dart';
import 'package:idea_vault/views/mixins/image_editor.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> with ImageEditorMixin {
  File? image;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: body()),
    );
  }

  Widget body() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox(
      width: double.maxFinite,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null) Image.file(image!),
          Align(
              child: ElevatedButton(onPressed: null, child: Text('Pick Image')))
        ],
      ),
    );
  }
}
