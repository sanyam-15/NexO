import 'package:flutter/material.dart';

class DsInput extends StatelessWidget {
  const DsInput({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.validator,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
    );
  }
}
