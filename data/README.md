# 数据文件说明

原始数据不随仓库分发。若已通过适用的数据集条款取得文件，请将无表头 CSV 放在 `data/raw/淘宝.csv`。Notebook 按 `user_id, item_id, category_id, behavior, timestamp` 五列读取，时间戳为 Unix 秒；`data/raw/` 和 CSV 已加入 `.gitignore`。

## 来源与许可

本机工程没有保留可核实的下载记录或授权条款。字段和数据集名称与天池官方的[《淘宝用户购物行为数据集》](https://tianchi.aliyun.com/dataset/649?lang=en-us)相符，但不能仅凭字段确认该文件来源或版本。天池要求按具体数据集协议使用，参见[天池数据集使用说明](https://tianchi.aliyun.com/specials/promotion/about)。请先核对实际来源及对应许可；本仓库不主张原始数据可再分发。

## 导入 MySQL

SQL 脚本会创建 `taobao_analysis` 数据库及原始表 `taobao`，但运行分析前需先将 CSV 导入该表。字段类型和顺序见 [`../sql/01_taobao_business_analysis.sql`](../sql/01_taobao_business_analysis.sql)。SQL 与 Power BI 查询当前使用 `taobao`；窗口分析表 `taobao_clean` 由 SQL 脚本生成。
