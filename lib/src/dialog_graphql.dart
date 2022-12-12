import 'package:flutter/material.dart';
import 'package:graphql/client.dart';

abstract class DialogGraphql {

  static Future<void> onChangeStatusFailed(BuildContext context, List<GraphQLError> errors) async {
    await showGraphQLErrorDialog(context, errors);
  }

  static Future<void> showGraphQLErrorDialog(BuildContext context, List<GraphQLError> errors, {String? code}) async {
    final message = errors.isEmpty == true || errors.first.message.isEmpty
        ? 'Máy chủ đang bảo trì.'
        : (code ?? '') + errors.first.message;

    return await _showSimpleDialog(context, message);
  }

  static Future<void> _showSimpleDialog(BuildContext context, String message) async {
    return await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

}