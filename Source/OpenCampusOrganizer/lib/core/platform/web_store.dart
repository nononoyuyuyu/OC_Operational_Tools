import '../ports.dart';
import 'memory_store.dart';

LocalStore createLocalStore() => MemoryStore();
CredentialStore createCredentialStore() => MemoryStore();
