import 'dart:convert';
import 'dart:io';

//import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'http.dart'; // make dio as global top-level variable
import 'routes/request.dart';
import 'package:crypto/crypto.dart';

// Must be top-level function
_parseAndDecode(String response) {
  return jsonDecode(response);
}

parseJson(String text) {
  return compute(_parseAndDecode, text);
}

void main() {
  // add interceptors
  //dio.interceptors.add(CookieManager(CookieJar()));
  // dio.interceptors.add(LogInterceptor());
  //(dio.transformer as DefaultTransformer).jsonDecodeCallback = parseJson;
  // dio.options.receiveTimeout = 15000;
//  (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
//      (client) {
//    client.findProxy = (uri) {
//      //proxy to my PC(charles)
//      return "PROXY 10.1.10.250:8888";
//    };
//  };
  _setDio();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _text = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Container(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          RaisedButton(
            child: Text("Request"),
            onPressed: () {
              Future.wait([
                reqDio.request(
                  '/Wikibit/entryfuc/gethome',
                  options: Options()..method = 'GET',
                  queryParameters: {'languageCode': 'zh-CN', 'countryCode': '156', 'version': '1.0.0', 'project': '1'},
                ),
                reqDio.request(
                  '/Wikibit/entryfuc/getall',
                  options: Options()..method = 'GET',
                  queryParameters: {'languageCode': 'zh-CN', 'countryCode': '156', 'version': '1.0.0', 'project': '1'},
                ),
              ]);
            },
          ),
          RaisedButton(
            child: Text("Request1"),
            onPressed: () {
              Future.wait([
                reqDio.request(
                  '/BitSurvey/survey/wikibit/latest/list',
                  options: Options()..method = 'GET',
                  queryParameters: {'languageCode': 'zh-CN', 'countryCode': '156', 'version': '1.0.0', 'project': '1'},
                ),
                reqDio.request(
                  '/BitArticle/wikibit/category',
                  options: Options()..method = 'GET',
                  queryParameters: {'languageCode': 'zh-CN', 'countryCode': '156', 'version': '1.0.0', 'project': '1'},
                ),
              ]);
            },
          ),
          RaisedButton(
            child: Text("clear token"),
            onPressed: () {
              _token = '';
            },
          ),
          RaisedButton(
            child: Text("clear dio"),
            onPressed: () {
              reqDio.close(force: true);
              reqDio.clear();
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Text(_text),
            ),
          )
        ]),
      ),
    );
  }
}

var reqDio = Dio(BaseOptions(
  connectTimeout: 15000,
  receiveTimeout: 15000,
  contentType: ContentType.json.primaryType + '/' + ContentType.json.subType,
  baseUrl: 'http://192.168.1.71:5100',
  headers: {},
));

var tokenDio = Dio(BaseOptions(
  connectTimeout: 1000,
  receiveTimeout: 1000,
  contentType: ContentType.json.primaryType + '/' + ContentType.json.subType,
  baseUrl: 'http://192.168.1.71:59103',
  headers: {},
));

String _token = '';

_setDio() {
  (reqDio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate = (client) {
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    client.findProxy = (uri) {
      return 'PROXY 192.168.1.202:8888';
    };
  };
  (tokenDio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate = (client) {
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    client.findProxy = (uri) {
      return 'PROXY 192.168.1.202:8888';
    };
  };
  tokenDio.interceptors.add(InterceptorsWrapper(onRequest: (e) => e, onResponse: (e) => e, onError: (e) => e));
  print('setDio');
  reqDio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options) {
        print('request-' + options.path);
        options.headers['Authorization'] = _token;
        return options;
      },
      onResponse: (Response response) async {
        //TODO: 这边偶然会出现Future<dynamic> 不是 FutureOr<Response<dynamic>> 错误
        print('response' + response.request.path);
        Map<String, dynamic> res =
        Map<String, dynamic>.from((response.data is Map) ? response.data : json.decode(response.data));
        int code = res['code'];
        if (code == 401) {
          RequestOptions options = response.request;
          String oldToken = options.headers['Authorization'];
          if (oldToken == _token) {
            print('首次遇到401');
            //首次遇到token过期
            reqDio.interceptors.requestLock.lock();
            reqDio.interceptors.responseLock.lock();
            reqDio.interceptors.errorLock.lock();
            try {
              await _requestToken();
              print('解锁');
              reqDio.interceptors.requestLock.unlock();
              reqDio.interceptors.responseLock.unlock();
              reqDio.interceptors.errorLock.unlock();
              _f() {
                // return reqDio.request(options.path, options: options);
                return reqDio.fetch(options);
              }
              return _f();
            } on DioError catch (e) {
              print('dio 错误' + e.toString());
              reqDio.interceptors.requestLock.unlock();
              reqDio.interceptors.responseLock.unlock();
              reqDio.interceptors.errorLock.unlock();
              reqDio.clear();

              return e;
            } finally {
              // reqDio.interceptors.requestLock.unlock();
              // reqDio.interceptors.responseLock.unlock();
              // reqDio.interceptors.errorLock.unlock();
            }
          } else {
            print('再次遇到401');
            //重新请求
            // return reqDio.request(options.path, options: options);
            return reqDio.fetch(options);
          }
        }
        return response;
      },
      onError: (DioError err) {
        print('DioError' + err.toString());
        return err;
      },
    ),
  );
}

int v = 1;
Future<void> _requestToken() async {
  String username = 'gsw';
  List<int> content = Utf8Encoder().convert(username);
  String pwd = md5.convert(content).toString().toUpperCase();
  print('请求token-begin');
  var res = await tokenDio.request(
    '/api/Permission/Login',
    queryParameters: {'username': username, 'password': pwd},
    options: Options(method: 'GET'),
  );
  _token = res.data['token_type'] + ' ' + res.data['access_token'];
  v += 1;
  _token = 'token' + v.toString();
  await Future.delayed(Duration(seconds: 1));
  print('请求token-end');
}

