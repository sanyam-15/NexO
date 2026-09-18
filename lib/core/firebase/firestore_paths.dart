class FirestorePaths {
  static String userDoc(String uid) => 'users/$uid';
  static String accounts(String uid) => 'users/$uid/accounts';
  static String transactions(String uid) => 'users/$uid/transactions';
  static String budgets(String uid) => 'users/$uid/budgets';
  static String recurring(String uid) => 'users/$uid/recurring';
  static String debts(String uid) => 'users/$uid/debts';
  static String syncMeta(String uid) => 'users/$uid/syncMeta/state';
}
