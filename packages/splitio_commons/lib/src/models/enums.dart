enum ImpressionsMode { optimized, debug, none }

/// Selects the unique-keys (MTK) wire shape `UniqueKeysRecorder` posts
/// (spec §19.6): `clientSide` posts `/v1/keys/cs` with `{k, fs}` (grouped by
/// matching key); `serverSide` posts `/v1/keys/ss` with `{f, ks}` (grouped
/// by feature).
enum UniqueKeysPayloadFormat { clientSide, serverSide }

enum ConsentStatus { granted, declined, unknown }

enum DataType { number, datetime }

enum ConditionType { rollout, whitelist }

enum CombinerEnum { and }
