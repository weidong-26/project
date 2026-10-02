# Power BI Dashboard 规格与实际实现

## PBIP 中的当前实际实现

Power BI Desktop 工作副本已另存为 PBIP/TMDL。报表定义包含下列三个页面及核心 Measure。当前 Power Query 源为 `MySQL.Database("localhost", "taobao_analysis")` 下的 `taobao` 表；PBIP 不含导入模型缓存，刷新需本机 MySQL 和对应数据。

本次已静态检查 PBIP 页面定义、字段映射、TMDL Measure 和连接字符串；由于当前 Power BI Desktop 会话不可用，未重新渲染页面或截取三页截图，视觉布局和趋势曲线未做运行时复核。

事实表：`taobao_analysis taobao`。当前没有额外的日期维、行为维、用户画像计算表或会话表。页签顺序为经营总览 → 用户行为分析 → 用户画像分析。

| 页面 | 视觉对象 | 视觉字段 / Measure | 解释口径 |
|---|---|---|---|
| 经营总览 | KPI 卡 | `[用户数]`、`[Active Users]`、`[Buy Users]`、`[购买转化率]`、`[PV/UV]` | 各卡受当前页面筛选上下文影响；当前画布显示用户数 988 千、购买用户 672 千、购买转化率 68.33%、PV/UV 90.81 |
| 经营总览 | 折线图 | X=`[date]`；Y=`[Active Users]` | 日活趋势；首日数据不完整 |
| 用户行为分析 | 漏斗图 | 类别=`[behavior]`；值=`[Active Users]` | pv/fav/cart/buy 各行为的去重用户覆盖数，不是顺序转化漏斗 |
| 用户行为分析 | 环图 | 图例=`[behavior]`；值=`[Active Users]` | 行为覆盖规模占比；用户可跨类别重复出现 |
| 用户行为分析 | 簇状柱形图 | X=`[hour]`；Y=`[Active Users]` | 0–23 时活跃用户分布 |
| 用户画像分析 | KPI 卡 | `[Active Users]`、`[高频购买用户（行为代理）]`、`[Buy Users]` | 第三页没有日期切片器，展示全观察期汇总 |
| 用户画像分析 | 环图 | 图例=`[behavior]`；值=`[Active Users]` | 按行为分类的用户覆盖，不是人口属性画像或互斥人群 |

行为值含义：`pv` 浏览、`fav` 收藏、`cart` 加购、`buy` 购买。

## 当前 Desktop 核心 Measure

模型已有 Measure：`Active Users`、`Buy Users`、`Cart Users`、`PV Users`。本项目新增或调整的核心公式：

```DAX
用户数 =
DISTINCTCOUNT ( 'taobao_analysis taobao'[user_id] )

页面浏览量 =
CALCULATE (
    COUNTROWS ( 'taobao_analysis taobao' ),
    'taobao_analysis taobao'[behavior] = "pv"
)

购买转化率 =
DIVIDE ( [Buy Users], [PV Users], 0 )

PV/UV =
DIVIDE ( [页面浏览量], [用户数], 0 )

高频购买用户（行为代理） =
COUNTROWS (
    FILTER (
        VALUES ( 'taobao_analysis taobao'[user_id] ),
        CALCULATE (
            COUNTROWS ( 'taobao_analysis taobao' ),
            'taobao_analysis taobao'[behavior] = "buy"
        ) >= 2
    )
)
```

## 跨产物口径核验

当前工作副本曾显示购买用户约 672 千、购买转化率 68.33%；项目内 SQL/Python 保存结果的分析窗口为 2017-11-24 至 2017-11-30，购买用户为 526,239、浏览用户为 980,561、购买用户/浏览用户为 53.67%。静态检查确认 PBIP 当前直接读取原始表 `taobao`，SQL 则建立窗口限定的 `taobao_clean`；两者来源范围不同，可能造成数值差异，但差异贡献尚未量化，不能视为已对齐。日期趋势字段与 Measure 已写入 PBIP，趋势数据形态仍需在 Desktop 中复核。

## 指标限制

- 购买转化率 = 购买用户 ÷ 浏览用户；该指标不强制浏览事件早于购买事件。
- PV/UV 的当前 Desktop 分母为全期去重用户 `[用户数]`，并非浏览用户 `[PV Users]`。
- 漏斗图只按行为类型统计用户覆盖；同一用户可以跨阶段出现，用户数不保证逐层递减。若需严格顺序漏斗，需另建按用户的事件时序计算，并明确是否要求同一会话/同一商品；当前数据没有会话 ID。
- 高频购买用户只是 `buy` 日志频次代理；数据没有订单金额、价格、利润、年龄、性别或地区字段。

## 后续模型扩展 DAX

[`measures.dax`](measures.dax) 还保留了显式日期/行为维、严格事件顺序漏斗和全期用户分层的扩展方案。该扩展方案当前未写入 Desktop 模型，不应误认为本 PBIX 已含这些辅助表和 Measure。
