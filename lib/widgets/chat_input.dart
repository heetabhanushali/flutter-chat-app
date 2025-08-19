import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSend;
  final bool isLoading;
  final String hintText;
  final bool autofocus;
  final Function(String)? onChanged;
  final Function(String)? onSubmitted;

  const ChatInput({
    super.key,
    required this.controller,
    this.onSend,
    this.isLoading = false,
    this.hintText = 'Message',
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  bool get _canSend => controller.text.trim().isNotEmpty && !isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        child: Row(
          children: [
            // Text Input Field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E5EA)),
                ),
                child: TextField(
                  controller: controller,
                  autofocus: autofocus,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    hintStyle: const TextStyle(color: Colors.grey),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: onSubmitted ?? (_) => onSend?.call(),
                  onChanged: onChanged ?? (_) {},
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Send Button
            GestureDetector(
              onTap: _canSend ? onSend : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _canSend 
                      ? const Color.fromRGBO(255, 109, 77, 1.0)
                      : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.arrow_upward,
                        color: _canSend 
                            ? Colors.white 
                            : Colors.grey[600],
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}