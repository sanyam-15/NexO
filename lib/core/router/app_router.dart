import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/presentation/accounts_screen.dart';
import '../../features/ai/presentation/ai_assistant_screen.dart';
import '../../features/ai/presentation/ai_hub_screen.dart';
import '../../features/ai/presentation/ai_insights_screen.dart';
import '../../features/ai/presentation/planning_screen.dart';
import '../../features/analytics/presentation/reports_screen.dart';
import '../../features/ai/presentation/ai_settings_screen.dart';
import '../../features/budgets/presentation/budgets_screen.dart';
import '../../features/capture/presentation/auto_capture_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/data/presentation/data_screen.dart';
import '../../features/documents/presentation/document_detail_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/home/presentation/home_customize_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/labels/presentation/labels_screen.dart';
import '../../features/notifications/presentation/reminders_screen.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../features/transactions/presentation/add_transaction_screen.dart';
import '../../features/transactions/presentation/batch_add_screen.dart';
import '../../features/transactions/presentation/capture_layout_screen.dart';
import '../../features/transactions/presentation/category_limits_screen.dart';
import '../../features/transactions/presentation/debts_screen.dart';
import '../../features/transactions/presentation/recurring_transactions_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/add',
        name: 'add',
        builder: (context, state) {
          final initialEntry = state.extra is FinanceEntry ? state.extra as FinanceEntry : null;
          return AddTransactionScreen(initialEntry: initialEntry);
        },
      ),
      GoRoute(
        path: '/recurring',
        name: 'recurring',
        builder: (context, state) => const RecurringTransactionsScreen(),
      ),
      GoRoute(
        path: '/debts',
        name: 'debts',
        builder: (context, state) => const DebtsScreen(),
      ),
      GoRoute(
        path: '/category-limits',
        name: 'category-limits',
        builder: (context, state) => const CategoryLimitsScreen(),
      ),
      GoRoute(
        path: '/accounts',
        name: 'accounts',
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: '/categories',
        name: 'categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/budgets',
        name: 'budgets',
        builder: (context, state) => const BudgetsScreen(),
      ),
      GoRoute(
        path: '/goals',
        name: 'goals',
        builder: (context, state) => const GoalsScreen(),
      ),
      GoRoute(
        path: '/ai-insights',
        name: 'ai-insights',
        builder: (context, state) => const AiInsightsScreen(),
      ),
      GoRoute(
        path: '/planning',
        name: 'planning',
        builder: (context, state) => const PlanningScreen(),
      ),
      GoRoute(
        path: '/ai-hub',
        name: 'ai-hub',
        builder: (context, state) => const AiHubScreen(),
      ),
      GoRoute(
        path: '/ai-assistant',
        name: 'ai-assistant',
        builder: (context, state) => const AiAssistantScreen(),
      ),
      GoRoute(
        path: '/ai-settings',
        name: 'ai-settings',
        builder: (context, state) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: '/auto-capture',
        name: 'auto-capture',
        builder: (context, state) => const AutoCaptureScreen(),
      ),
      GoRoute(
        path: '/data',
        name: 'data',
        builder: (context, state) => const DataScreen(),
      ),
      GoRoute(
        path: '/transactions',
        name: 'transactions',
        builder: (context, state) => const TransactionsScreen(),
      ),
      GoRoute(
        path: '/reminders',
        name: 'reminders',
        builder: (context, state) => const RemindersScreen(),
      ),
      GoRoute(
        path: '/labels',
        name: 'labels',
        builder: (context, state) => const LabelsScreen(),
      ),
      GoRoute(
        path: '/home-customize',
        name: 'home-customize',
        builder: (context, state) => const HomeCustomizeScreen(),
      ),
      GoRoute(
        path: '/reports',
        name: 'reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/documents',
        name: 'documents',
        builder: (context, state) => const DocumentsScreen(),
      ),
      GoRoute(
        path: '/document-detail',
        name: 'document-detail',
        builder: (context, state) => DocumentDetailScreen(documentId: state.extra as String),
      ),
      GoRoute(
        path: '/capture-layout',
        name: 'capture-layout',
        builder: (context, state) => const CaptureLayoutScreen(),
      ),
      GoRoute(
        path: '/batch-add',
        name: 'batch-add',
        builder: (context, state) => const BatchAddScreen(),
      ),
    ],
  );
});
