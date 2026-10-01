/// 重量单位换算（V1.1.1 辅助工具）。
///
/// 训练记录统一以 kg 存储，本工具只做纯计算，
/// 不读写数据库、不改变任何记录逻辑。
library;

/// 精确换算系数
const double kgPerPound = 0.45359237;
const double poundsPerKg = 2.2046226218;

/// 磅 → 公斤
double poundsToKg(double pounds) => pounds * kgPerPound;

/// 公斤 → 磅
double kgToPounds(double kg) => kg * poundsPerKg;

/// 训练记录参考值：四舍五入到 0.1 kg（力量训练不会记录 31.7514… 这种数）。
double roundToTrainingKg(double kg) => (kg * 10).roundToDouble() / 10;
