import 'package:flutter/material.dart';

class MathInputBar extends StatelessWidget {
  final TextEditingController controller;

  const MathInputBar({super.key, required this.controller});

  void _insertOperator(String op) {
    final text = controller.text;
    final selection = controller.selection;
    final cursorPos = selection.isValid ? selection.baseOffset : text.length;

    final newText =
        text.substring(0, cursorPos) + op + text.substring(cursorPos);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorPos + op.length),
    );
  }

  void _moveCursor(int direction) {
    final selection = controller.selection;
    if (!selection.isValid) return;

    // If there's a range selection, collapse to the appropriate edge
    if (!selection.isCollapsed) {
      final offset = direction < 0 ? selection.start : selection.end;
      controller.selection = TextSelection.collapsed(offset: offset);
      return;
    }

    final newOffset = (selection.baseOffset + direction).clamp(
      0,
      controller.text.length,
    );
    controller.selection = TextSelection.collapsed(offset: newOffset);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF1C1C1E),
      child: Row(
        children: [
          _buildBarButton('<', () => _moveCursor(-1)),
          _buildOperatorDivider(),
          _buildBarButton('>', () => _moveCursor(1)),
          _buildOperatorDivider(),
          _buildBarButton('+', () => _insertOperator('+')),
          _buildOperatorDivider(),
          _buildBarButton('-', () => _insertOperator('-')),
          _buildOperatorDivider(),
          _buildBarButton('*', () => _insertOperator('*')),
          _buildOperatorDivider(),
          _buildBarButton('/', () => _insertOperator('/')),
        ],
      ),
    );
  }

  Widget _buildBarButton(String label, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: const Color(0xFF323236),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperatorDivider() {
    return const SizedBox(width: 8);
  }
}
