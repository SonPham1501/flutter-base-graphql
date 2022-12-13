// ignore_for_file: file_names, depend_on_referenced_packages

import 'dart:io' as io;

import 'package:artemis/schema/graphql_query.dart';
import 'package:flutter/rendering.dart';
import 'package:graphql/client.dart';
import 'package:http/io_client.dart' as http;
import 'package:json_annotation/json_annotation.dart' as json_annotation;

import '../base_graphql.dart';

// final GraphQLApiClient graphQLApiClient = locator<GraphQLApiClient>();

final networkOnlyPolicies = Policies(
  fetch: FetchPolicy.cacheAndNetwork,
);

GraphQLClient _buildClient({
  required String uri,
  String? finger,
  Future<String> Function()? funcGetToken,
  String? fixedToken,
}) {
  io.HttpClient httpClient = io.HttpClient();
  httpClient.badCertificateCallback = (io.X509Certificate cert, String host, int port) => true;
  http.IOClient ioClient = http.IOClient(httpClient);

  final httpLink = HttpLink(
    uri,
    httpClient: ioClient,
    // httpClient: LoggerHttpClient(http.Client()),
  );

  final newAuthLink = AuthLink(
    headerKey: 'Authorization',
    getToken: () async {
      if (fixedToken != null) {
        return fixedToken;
      }
      if (funcGetToken == null) return null;
      return 'Bearer ${await funcGetToken.call()}';
    },
  );

  Link link;

  if (finger != null) {
    final newFinger = AuthLink(
      headerKey: 'Finger',
      getToken: () async {
        return finger;
      },
    );
    link = newAuthLink.concat(newFinger).concat(httpLink);
  } else {
    link = newAuthLink.concat(httpLink);
  }

  return GraphQLClient(
    cache: GraphQLCache(),
    link: link,
    defaultPolicies: DefaultPolicies(
      watchQuery: networkOnlyPolicies,
      query: networkOnlyPolicies,
      mutate: networkOnlyPolicies,
    ),
  );
}

class GraphQLApiClient {

  static Future<bool> Function()? refeshToken;
  static Future Function()? actionNotRefeshToken;

  GraphQLApiClient({
    required String uri,
    String? finger,
    Future<String> Function()? funcGetToken,
  }) : client = _buildClient(uri: uri, finger: finger, funcGetToken: funcGetToken);

  GraphQLApiClient.withFixedToken({
    required String uri,
    required String fixedToken,
    String? finger,
    Future<String> Function()? funcGetToken,
  }) : client = _buildClient(uri: uri, fixedToken: fixedToken, finger: finger, funcGetToken: funcGetToken);

  final GraphQLClient client;

  Future<NetworkResourceState<T>> query<T>(
    GraphQLQuery query,
    {int countRequest = 1}
  ) async {
    final result = await client.query(QueryOptions(
      document: query.document,
      variables: query.variables == null ? {} : query.variables!.toJson(),
    ));

    if (result.hasException) {
      if (_hasUnauthorizedError(result.exception!.graphqlErrors)) {
        debugPrint('errr ---');
        if (GraphQLApiClient.refeshToken != null && GraphQLApiClient.actionNotRefeshToken != null) {
          var isGetAccessTokenSuccess = await GraphQLApiClient.refeshToken!.call();
          if (isGetAccessTokenSuccess) {
            if (countRequest < 2) {
              return await this.query(query, countRequest: countRequest + 1);
            } else {
              await GraphQLApiClient.actionNotRefeshToken!.call();
            }
          } else {
            await GraphQLApiClient.actionNotRefeshToken!.call();
          }
        } else if (GraphQLApiClient.actionNotRefeshToken != null) {
          await GraphQLApiClient.actionNotRefeshToken!.call();
        }
        // navigationService.logout();
      } else {
        // if (_hasStopAccountError(result.exception!.graphqlErrors)) {
        //   final loginId = result.exception!.graphqlErrors.first.extensions!['details']['login_id'];

        //   navigationService?.showStopAccountMessage(
        //     result.exception!.graphqlErrors.first.message,
        //     loginId,
        //   );
        // }
        debugPrint('result.exception ${result.exception}');
        return NetworkResourceState<T>.error(result.exception!.graphqlErrors);
      }
    }
    final data = query.parse(result.data as Map<String, dynamic>) as T;
    return NetworkResourceState<T>(data);
  }

  bool _hasUnauthorizedError(List<GraphQLError> errors) => errors.any((e) => _isUnauthorizedError(e));

  bool _isUnauthorizedError(GraphQLError error) => error.extensions?.containsKey('code') == true && error.extensions!['code'].toString() == '401';

  // bool _hasStopAccountError(List<GraphQLError> errors) {
  //   return errors.any((e) => _isStopAccountError(e));
  // }

  // bool _isStopAccountError(GraphQLError error) {
  //   return error.extensions?.containsKey('code') == true &&
  //       error.extensions!['code'] == 'BAD_REQUEST';
  // }

  Future<NetworkResourceState<T>> mutation<T, U extends json_annotation.JsonSerializable>(
    GraphQLQuery<T, U> query, {
    int countRequest = 1
  }) async {
    final result = await client.mutate(MutationOptions(
      document: query.document,
      variables: query.variables == null ? {} : query.variables!.toJson(),
    ));

    if (result.hasException) {
      if (_hasUnauthorizedError(result.exception!.graphqlErrors)) {
        debugPrint('errr ---');
        if (GraphQLApiClient.refeshToken != null && GraphQLApiClient.actionNotRefeshToken != null) {
          var isGetAccessTokenSuccess = await GraphQLApiClient.refeshToken!.call();
          if (isGetAccessTokenSuccess) {
            if (countRequest < 2) {
              return await mutation(query, countRequest: countRequest + 1);
            } else {
              await GraphQLApiClient.actionNotRefeshToken!.call();
            }
          } else {
            await GraphQLApiClient.actionNotRefeshToken!.call();
          }
        } else if (GraphQLApiClient.actionNotRefeshToken != null) {
          await GraphQLApiClient.actionNotRefeshToken!.call();
        }
        // navigationService.logout();
      } else {
        // if (_hasStopAccountError(result.exception!.graphqlErrors)) {
        //   final loginId = result.exception!.graphqlErrors.first.extensions!['details']['login_id'];

        //   navigationService?.showStopAccountMessage(
        //     result.exception!.graphqlErrors.first.message,
        //     loginId,
        //   );
        // }
        debugPrint('result.exception ${result.exception}');
        return NetworkResourceState<T>.error(result.exception!.graphqlErrors);
      }
    }

    final errors = convertToError(result.data, query.operationName!);
    if (errors.isNotEmpty) {
      // response has `data.<operation-name>.errors`
      return NetworkResourceState<T>.error(errors);
    }

    try {
      final data = query.parse(result.data as Map<String, dynamic>);
      return NetworkResourceState<T>(data);
    } on Exception {
      // illegal error.
      //FirebaseCrashlytics.instance.recordError(e, trace);
      return NetworkResourceState<T>.error([]);
    }
  }

  // use this method if you want to handle data and errors.
  Future<QueryResult> mutationRaw(GraphQLQuery query) async {
    final result = await client.mutate(MutationOptions(
      document: query.document,
      variables: query.variables == null ? {} : query.variables!.toJson(),
    ));

    return result;
  }

  List<GraphQLError> convertToError(dynamic data, String operationName) {
    final map = data as Map<String, dynamic>;
    if (!map.containsKey(operationName)) {
      return [];
    }
    final operationMap = map[operationName] as Map<String, dynamic>;
    if (!operationMap.containsKey('errors')) {
      return [];
    }

    final errorsMap = operationMap['errors'] as List<dynamic>;
    return errorsMap.map((e) => GraphQLError(
      message: e['message'] as String,
      path: e['path'] as List<dynamic>,
    )).toList();
  }

  List<GraphQLError> convertToErrorFromMessageAndSubject(dynamic data, String operationName) {
    final map = data as Map<String, dynamic>;
    if (!map.containsKey(operationName)) {
      return [];
    }
    final operationMap = map[operationName] as Map<String, dynamic>;
    if (!operationMap.containsKey('errors')) {
      return [];
    }
    final errors = operationMap['errors'] as List<dynamic>;
    final List<GraphQLError> result = [];

    for (var e in errors) {
      if (e.containsKey('message')) {
        if (e.containsKey('subject') && e['subject'] != null) {
          final item = '${e['subject']}${e['message']}';
          result.add(GraphQLError(message: item));
        } else {
          final item = '${e['message']}';
          result.add(GraphQLError(message: item));
        }
      }
    }

    return result;
  }
}
