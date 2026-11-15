-- Отчет сколько денег (FOOD-108)
-- Месяцы строятся рекурсивным CTE, месяцы без заказов выводятся с нулями.

SET search_path TO dunaev_food, exts;

CREATE OR REPLACE VIEW dunaev_food.how_much_money AS
WITH RECURSIVE
delivered AS (
    SELECT date_trunc('month', o.order_timestamp)::date AS month_start,
           o.order_amount,
           o.total_amount
    FROM dunaev_food."order" o
    WHERE o.status = 'доставлен'
),
bounds AS (
    SELECT min(month_start) AS first_month, max(month_start) AS last_month
    FROM delivered
),
months AS (
    SELECT b.first_month AS month_start
    FROM bounds b
    WHERE b.first_month IS NOT NULL
    UNION ALL
    SELECT (m.month_start + interval '1 month')::date
    FROM months m
    CROSS JOIN bounds b
    WHERE m.month_start < b.last_month
),
sales AS (
    SELECT d.month_start,
           sum(d.order_amount) AS sum_no_commission,
           sum(d.total_amount) AS sum_with_commission
    FROM delivered d
    GROUP BY d.month_start
),
pay AS (
    SELECT make_date(cp.year, cp.month, 1) AS month_start,
           sum(cp.amount) AS courier_pay
    FROM dunaev_food.courier_pay cp
    GROUP BY 1
),
base AS (
    SELECT m.month_start,
           coalesce(s.sum_no_commission, 0)::numeric   AS sum_no_commission,
           coalesce(s.sum_with_commission, 0)::numeric AS sum_with_commission,
           coalesce(p.courier_pay, 0)::numeric         AS courier_pay
    FROM months m
    LEFT JOIN sales s ON s.month_start = m.month_start
    LEFT JOIN pay   p ON p.month_start = m.month_start
)
SELECT to_char(b.month_start, 'YYYY-MM')::text                         AS year_month,
       b.sum_no_commission,
       b.sum_with_commission,
       (b.sum_with_commission - b.sum_no_commission)                   AS commission,
       lag(b.sum_with_commission - b.sum_no_commission)
           OVER (ORDER BY b.month_start)                               AS prev_commission,
       (b.sum_with_commission - b.sum_no_commission)
         - lag(b.sum_with_commission - b.sum_no_commission)
               OVER (ORDER BY b.month_start)                           AS commission_diff,
       b.courier_pay,
       (b.sum_with_commission - b.sum_no_commission) - b.courier_pay   AS net_profit
FROM base b
ORDER BY b.month_start;
