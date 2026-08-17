import 'package:flutter/material.dart';
import 'package:fmlink/models/publisher_model.dart';
import 'package:go_router/go_router.dart';
import 'package:fmlink/screens/auth/login_screen.dart';
import 'package:fmlink/screens/discover/discover_screen.dart';
import 'package:fmlink/screens/publish/publish_screen.dart';
import 'package:fmlink/screens/publish/publication_detail_screen.dart';
import 'package:fmlink/screens/publish/publication_desc_screen.dart';
import 'package:fmlink/screens/publish/publisher_detail_screen.dart';
import 'package:fmlink/screens/publish/publication_source_list_screen.dart';
import 'package:fmlink/screens/resource/resource_list_screen.dart';
import 'package:fmlink/screens/history/history_screen.dart';
import 'package:fmlink/screens/history/link_management_screen.dart';
import 'package:fmlink/screens/profile/profile_screen.dart';
import 'package:fmlink/screens/profile/about_screen.dart';
import 'package:fmlink/screens/profile/faq_screen.dart';
import 'package:fmlink/screens/profile/account_security_screen.dart';
import 'package:fmlink/screens/profile/bind_phone_screen.dart';
import 'package:fmlink/screens/profile/set_password_screen.dart';
import 'package:fmlink/screens/profile/device_management_screen.dart';
import 'package:fmlink/screens/profile/delete_account_screen.dart';
import 'package:fmlink/screens/profile/my_like_screen.dart';
import 'package:fmlink/screens/scan/scan_screen.dart';
import 'package:fmlink/screens/scan/scan_result_screen.dart';
import 'package:fmlink/screens/scan/scan_help_screen.dart';
import 'package:fmlink/screens/scan/book_help_screen.dart';
import 'package:fmlink/screens/webview/webview_screen.dart';
import 'package:fmlink/screens/main/main_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MainScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/discover',
        builder: (context, state) => const DiscoverScreen(),
      ),
      GoRoute(
        path: '/publish',
        builder: (context, state) => const PublishScreen(),
      ),
      GoRoute(
        path: '/publication-detail',
        builder: (context, state) {
          final goodsId = state.uri.queryParameters['goodsId'] ?? '';
          return PublicationDetailScreen(goodsId: goodsId);
        },
      ),
      GoRoute(
        path: '/publication-desc',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          final title = data?['title'] ?? '出版物简介';
          final content = data?['content'] ?? '';
          return PublicationDescScreen(title: title, content: content);
        },
      ),
      GoRoute(
        path: '/publisher-detail',
        builder: (context, state) {
          final publisher = state.extra as PublisherModel?;
          return PublisherDetailScreen(publisher: publisher!);
        },
      ),
      GoRoute(
        path: '/publication-source-list',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          return PublicationSourceListScreen(
            goodsId: data?['goodsId'] ?? '',
            goodsName: data?['goodsName'] ?? '',
            goodsImage: data?['goodsImage'] ?? '',
            serviceCode: data?['serviceCode'] ?? '',
            prefixCode: data?['prefixCode'] ?? '',
            versionCode: data?['versionCode'] ?? 1,
            resourceFormats: data?['resourceFormats'] ?? [],
          );
        },
      ),
      GoRoute(
        path: '/resource',
        builder: (context, state) => const ResourceListScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/link-management',
        builder: (context, state) => const LinkManagementScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const MyScreen(),
      ),
      GoRoute(
        path: '/profile/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/profile/faq',
        builder: (context, state) => const FaqScreen(),
      ),
      GoRoute(
        path: '/profile/account-security',
        builder: (context, state) => const AccountSecurityScreen(),
      ),
      GoRoute(
        path: '/profile/bind-phone',
        builder: (context, state) => const BindPhoneScreen(),
      ),
      GoRoute(
        path: '/profile/set-password',
        builder: (context, state) => const SetPasswordScreenWithExtra(),
      ),
      GoRoute(
        path: '/profile/device-management',
        builder: (context, state) => const DeviceManagementScreen(),
      ),
      GoRoute(
        path: '/profile/delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/profile/my-like',
        builder: (context, state) => const MyLikeScreen(),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/scan/result',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          return ScanResultScreen(
            isliCode: data?['isliCode'] ?? '',
            resultData: data?['data'],
          );
        },
      ),
      GoRoute(
        path: '/scan/help',
        builder: (context, state) => const ScanHelpScreen(),
      ),
      GoRoute(
        path: '/scan/book-help',
        builder: (context, state) => const BookHelpScreen(),
      ),
      GoRoute(
        path: '/webview',
        builder: (context, state) {
          final url = state.uri.queryParameters['url'] ?? '';
          final title = state.uri.queryParameters['title'];
          return WebViewScreen(url: url, title: title);
        },
      ),
    ],
  );
}