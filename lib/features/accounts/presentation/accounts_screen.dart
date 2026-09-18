import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../transactions/domain/currency.dart';
import '../domain/account.dart';
import '../domain/accounts_provider.dart';
import 'account_editor.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider);
    final balances = ref.watch(accountBalancesProvider);
    final netWorth = ref.watch(netWorthProvider);
    final theme = Theme.of(context);

    return DsScreenScaffold(
      title: 'Cuentas',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAccountEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Cuenta'),
      ),
      children: [
        const DsFeatureHeader(
          title: 'Cuentas y patrimonio',
          subtitle: 'Saldo por cuenta, transferencias y patrimonio neto en un solo lugar.',
          icon: Icons.account_balance_wallet_rounded,
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patrimonio neto', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(
                formatMoney(netWorth),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: netWorth >= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${accounts.length} cuenta${accounts.length == 1 ? '' : 's'} activa${accounts.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          const DsEmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Sin cuentas',
            message: 'Crea tu primera cuenta para empezar a llevar saldos.',
          )
        else
          ...accounts.map((a) => _AccountTile(account: a, balance: balances[a.id] ?? 0)),
      ],
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account, required this.balance});

  final Account account;
  final double balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DsCard(
        padding: const EdgeInsets.all(14),
        onTap: () => showAccountEditor(context, ref, existing: account),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: account.colorValue.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(account.icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${account.type.label} · ${account.currency}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              // Balance is computed in MXN; the account's own currency is
              // already shown as metadata in the subtitle above.
              formatMoney(balance),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: balance >= 0 ? theme.colorScheme.onSurface : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
