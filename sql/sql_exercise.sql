-- ==========================================================
-- 6.D.1  Monthly late rate overall and by ship_mode
-- ==========================================================

WITH base AS (
    SELECT
        po.order_id,
        po.ship_mode,
        DATE_TRUNC('month', po.order_date) AS year_month,
        CASE 
            WHEN d.actual_delivery_date > po.promised_date THEN 1
            ELSE 0
        END AS late_flag
    FROM purchase_orders po
    LEFT JOIN deliveries d ON po.order_id = d.order_id
    WHERE po.cancelled = 0
      AND po.order_date >= DATE '2025-04-01'
      AND po.order_date <= DATE '2025-06-30'
)

-- (a) Overall monthly late rate
SELECT 
    year_month,
    'ALL' AS ship_mode,
    COUNT(*) AS orders,
    AVG(late_flag::float) AS late_rate
FROM base
GROUP BY year_month

UNION ALL

-- (b) By ship_mode monthly late rate
SELECT 
    year_month,
    ship_mode,
    COUNT(*) AS orders,
    AVG(late_flag::float) AS late_rate
FROM base
GROUP BY year_month, ship_mode
ORDER BY year_month, ship_mode;

-- ==========================================================
-- 6.D.2  Top 5 suppliers by volume (orders) with late_rate
-- ==========================================================

supplier_agg AS (
    SELECT
        b.supplier_id,
        COUNT(*) AS orders,
        AVG(b.late_flag::float) AS late_rate
    FROM base b
    GROUP BY b.supplier_id
)
SELECT
    sa.supplier_id,
    s.supplier_name,
    sa.orders,
    sa.late_rate
FROM supplier_agg sa
LEFT JOIN suppliers s ON sa.supplier_id = s.supplier_id
ORDER BY sa.orders DESC, sa.late_rate DESC, sa.supplier_id
LIMIT 5;

-- ==========================================================
-- 6.D.3  Supplier trailing 90-day late rate strictly before order_date
-- ==========================================================

SELECT
    ob.order_id,
    ob.supplier_id,
    ob.order_date,
    (
        SELECT AVG(prev.late_flag::float)
        FROM order_base prev
        WHERE prev.supplier_id = ob.supplier_id
          AND prev.order_date < ob.order_date                
          AND prev.order_date >= ob.order_date - INTERVAL '90 days'
    ) AS supplier_trailing_90d_late_rate
FROM order_base ob
ORDER BY ob.order_date;

-- ==========================================================
-- 6.D.4  Detect overlapping price windows per (supplier_id, sku)
-- ==========================================================

SELECT
    p1.supplier_id,
    p1.sku,
    p1.valid_from AS window1_start,
    p1.valid_to   AS window1_end,
    p2.valid_from AS window2_start,
    p2.valid_to   AS window2_end
FROM price_lists p1
JOIN price_lists p2
  ON p1.supplier_id = p2.supplier_id
 AND p1.sku = p2.sku
 AND p1.valid_from < p2.valid_to
 AND p1.valid_to   > p2.valid_from
 AND p1.valid_from < p2.valid_from   
ORDER BY p1.supplier_id, p1.sku, p1.valid_from;

-- ==========================================================
-- 6.D.5  Attach valid price at order date, normalize to EUR, compute order_value_eur
-- ==========================================================

WITH orders AS (
    SELECT
        po.order_id,
        po.supplier_id,
        po.sku,
        po.order_date,
        po.qty
    FROM purchase_orders po
    WHERE po.cancelled = 0
),
candidate_prices AS (
    SELECT
        o.order_id,
        p.supplier_id,
        p.sku,
        p.valid_from,
        p.valid_to,
        p.currency,
        p.price_per_uom,
        p.min_qty,
        CASE
            WHEN o.order_date >= p.valid_from
             AND (p.valid_to IS NULL OR o.order_date <= p.valid_to)
             AND (p.min_qty IS NULL OR p.min_qty <= o.qty)
            THEN 1 ELSE 0
        END AS is_valid_for_order
    FROM orders o
    JOIN price_lists p
      ON p.supplier_id = o.supplier_id
     AND p.sku         = o.sku
),
best_price AS (
    SELECT
        cp.order_id,
        cp.supplier_id,
        cp.sku,
        cp.valid_from,
        cp.valid_to,
        cp.currency,
        cp.price_per_uom,
        cp.min_qty,
        ROW_NUMBER() OVER (
            PARTITION BY cp.order_id
            ORDER BY
                cp.min_qty DESC NULLS LAST,
                cp.valid_from DESC
        ) AS rn
    FROM candidate_prices cp
    WHERE cp.is_valid_for_order = 1
),
chosen AS (
    SELECT
        b.order_id,
        b.supplier_id,
        b.sku,
        b.valid_from,
        b.valid_to,
        b.currency,
        b.price_per_uom,
        b.min_qty
    FROM best_price b
    WHERE b.rn = 1
)
SELECT
    o.order_id,
    o.supplier_id,
    o.sku,
    o.order_date,
    o.qty,
    c.valid_from,
    c.valid_to,
    c.currency,
    c.price_per_uom,
    CASE
        WHEN c.currency = 'EUR' THEN c.price_per_uom
        WHEN c.currency = 'USD' THEN c.price_per_uom * 0.92  
        ELSE NULL
    END AS unit_price_eur,
    o.qty * CASE
        WHEN c.currency = 'EUR' THEN c.price_per_uom
        WHEN c.currency = 'USD' THEN c.price_per_uom * 0.92
        ELSE NULL
    END AS order_value_eur
FROM orders o
LEFT JOIN chosen c
  ON c.order_id = o.order_id
ORDER BY o.order_date, o.order_id;


-- ==========================================================
-- 6.D.6  Flag price anomalies via z on ln(price_eur) per series; return top 10 |z|
-- ==========================================================

WITH prices_eur AS (
    SELECT
        p.supplier_id,
        p.sku,
        p.valid_from,
        p.valid_to,
        p.currency,
        p.price_per_uom,
        CASE
            WHEN p.currency = 'EUR' THEN p.price_per_uom
            WHEN p.currency = 'USD' THEN p.price_per_uom * 0.92
            ELSE NULL
        END AS price_eur
    FROM price_lists p
),
with_log AS (
    SELECT
        supplier_id,
        sku,
        valid_from,
        valid_to,
        currency,
        price_per_uom,
        price_eur,
        CASE
            WHEN price_eur IS NOT NULL AND price_eur > 0 THEN LN(price_eur)
            ELSE NULL
        END AS ln_price_eur
    FROM prices_eur
),
series_stats AS (
    SELECT
        supplier_id,
        sku,
        AVG(ln_price_eur)                AS mean_ln,
        STDDEV_SAMP(ln_price_eur)        AS sd_ln
    FROM with_log
    WHERE ln_price_eur IS NOT NULL
    GROUP BY supplier_id, sku
),
scored AS (
    SELECT
        w.supplier_id,
        w.sku,
        w.valid_from,
        w.valid_to,
        w.currency,
        w.price_per_uom,
        w.price_eur,
        w.ln_price_eur,
        -- classic z-score on ln(price_eur); guard against sd=0
        (w.ln_price_eur - s.mean_ln) / NULLIF(s.sd_ln, 0) AS z_ln_price
    FROM with_log w
    JOIN series_stats s
      ON s.supplier_id = w.supplier_id
     AND s.sku = w.sku
    WHERE w.ln_price_eur IS NOT NULL
)
SELECT
    supplier_id,
    sku,
    valid_from,
    valid_to,
    currency,
    price_per_uom,
    price_eur,
    ln_price_eur,
    z_ln_price,
    ABS(z_ln_price) AS abs_z
FROM scored
WHERE z_ln_price IS NOT NULL
ORDER BY ABS(z_ln_price) DESC
LIMIT 10;

-- ==========================================================
-- 6.D.7  Incoterm × distance buckets: average delay_days and count
-- ==========================================================

WITH base AS (
    SELECT
        po.order_id,
        po.incoterm,
        po.distance_km,
        CASE
            WHEN po.distance_km IS NULL              THEN 'unknown'
            WHEN po.distance_km <= 500               THEN '<=500km'
            WHEN po.distance_km > 500  AND po.distance_km <= 2000 THEN '500-2000km'
            WHEN po.distance_km > 2000 AND po.distance_km <= 5000 THEN '2000-5000km'
            ELSE '>5000km'
        END AS distance_bucket,
        po.promised_date,
        d.actual_delivery_date,
        EXTRACT(DAY FROM (d.actual_delivery_date - po.promised_date))::int AS delay_days
    FROM purchase_orders po
    LEFT JOIN deliveries d ON d.order_id = po.order_id
    WHERE po.cancelled = 0
      AND po.order_date >= DATE '2025-04-01'
      AND po.order_date <= DATE '2025-06-30'
      AND d.actual_delivery_date IS NOT NULL
)
SELECT
    incoterm,
    distance_bucket,
    COUNT(*)                             AS orders,
    AVG(delay_days)::numeric(10,2)       AS avg_delay_days
FROM base
GROUP BY incoterm, distance_bucket
ORDER BY incoterm, 
         CASE distance_bucket
            WHEN '<=500km' THEN 1
            WHEN '500-2000km' THEN 2
            WHEN '2000-5000km' THEN 3
            WHEN '>5000km' THEN 4
            ELSE 5
         END;

-- ==========================================================
-- 6.D.Bonus  High-risk bucket vs. low-risk: compare late_rate
-- ==========================================================

WITH valid_orders AS (
  SELECT
      po.order_id,
      po.order_date,
      po.promised_date,
      CASE WHEN d.actual_delivery_date > po.promised_date THEN 1 ELSE 0 END AS late_flag
  FROM purchase_orders po
  LEFT JOIN deliveries d ON d.order_id = po.order_id
  WHERE po.cancelled = 0
    AND po.order_date >= DATE '2025-04-01'
    AND po.order_date <= DATE '2025-06-30'
),
scored AS (
  SELECT
      vo.order_id,
      vo.late_flag,
      pr.p_late,
      NTILE(10) OVER (ORDER BY pr.p_late DESC) AS risk_decile
  FROM valid_orders vo
  JOIN predictions pr ON pr.order_id = vo.order_id
),
bucketed AS (
  SELECT
      CASE WHEN risk_decile = 1 THEN 'HIGH_10pct' ELSE 'LOW_90pct' END AS risk_bucket,
      late_flag
  FROM scored
)
SELECT
    risk_bucket,
    COUNT(*)                             AS orders,
    AVG(late_flag::float)                AS late_rate
FROM bucketed
GROUP BY risk_bucket
ORDER BY risk_bucket;
