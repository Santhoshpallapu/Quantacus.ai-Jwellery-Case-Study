-- Quantacus Jewellery Growth Case Study
-- BigQuery Standard SQL
-- Purpose:
--   Diagnose the reported ROAS gap, identify product-level allocation inefficiency,
--   validate catalogue/feed signals, and provide measurement tables for a controlled
--   pathway toward 5x ROAS without assuming that 5x will be achieved automatically.
--
-- Important:
--   1) BigQuery is the source of truth for all numeric outputs.
--   2) The supplied dataset does NOT reproduce the reported 3.4x baseline.
--   3) Recent dates can be affected by attribution lag; use mature windows for decisions.
--   4) Products is a historical/snapshot table and must be deduplicated before joining.
--   5) Do not interpret NO_CATALOGUE_SNAPSHOT as out-of-stock.
--   6) Margin data and a dedicated search-query/change-history table are not supplied.
--
-- Source tables:
--   `quantacusinterviewproject.interview_ayad.Products`
--   `quantacusinterviewproject.interview_ayad.list_obj`
--   `quantacusinterviewproject.interview_ayad.p_ads_Campaign`
--   `quantacusinterviewproject.interview_ayad.p_ads_Campaignbasicstats`
--   `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`

DECLARE analysis_start DATE DEFAULT '2026-08-09';
DECLARE analysis_end DATE DEFAULT '2026-09-07';

-- Campaign-level comparison window used for the account baseline.
DECLARE baseline_start DATE DEFAULT analysis_start;
DECLARE baseline_end DATE DEFAULT analysis_end;

-- Campaign analysed in detail for product-allocation diagnostics.
DECLARE focus_campaign_id INT64 DEFAULT 23967670213;

-- Minimum spend used to identify commercially meaningful products.
-- This is a review threshold, not an automatic pause rule.
DECLARE meaningful_spend_threshold NUMERIC DEFAULT 1000;

-- ============================================================
-- 01. ACCOUNT BASELINE — CAMPAIGN LEVEL
-- Purpose:
--   Establish the latest mature 30-day campaign-level baseline.
--   ROAS is always calculated from aggregate value / aggregate spend,
--   rather than averaging daily or campaign-level ROAS values.
-- ============================================================

WITH campaign_baseline AS (
  SELECT
    segments_date AS performance_date,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks,
    SUM(metrics_impressions) AS impressions
  FROM `quantacusinterviewproject.interview_ayad.p_ads_Campaignbasicstats`
  WHERE segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY performance_date
),
campaign_baseline_total AS (
  SELECT
    SUM(spend) AS spend,
    SUM(conversion_value) AS conversion_value,
    SUM(conversions) AS conversions,
    SUM(clicks) AS clicks,
    SUM(impressions) AS impressions
  FROM campaign_baseline
)
SELECT
  baseline_start AS analysis_start,
  baseline_end AS analysis_end,
  spend,
  conversion_value,
  conversions,
  clicks,
  impressions,
  SAFE_DIVIDE(conversion_value, spend) AS roas,
  SAFE_DIVIDE(conversions, clicks) AS cvr,
  SAFE_DIVIDE(spend, clicks) AS cpc,
  SAFE_DIVIDE(conversion_value, conversions) AS aov
FROM campaign_baseline_total;

-- ============================================================
-- 02. ACCOUNT BASELINE — PRODUCT LEVEL
-- Purpose:
--   Establish the corresponding product-level view and make the
--   population difference explicit.
-- ============================================================

WITH product_baseline AS (
  SELECT
    segments_product_item_id AS product_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks,
    SUM(metrics_impressions) AS impressions
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id
  HAVING SUM(metrics_cost_micros) > 0
),
product_baseline_total AS (
  SELECT
    SUM(spend) AS spend,
    SUM(conversion_value) AS conversion_value,
    SUM(conversions) AS conversions,
    SUM(clicks) AS clicks,
    SUM(impressions) AS impressions,
    COUNT(*) AS measured_product_count
  FROM product_baseline
)
SELECT
  baseline_start AS analysis_start,
  baseline_end AS analysis_end,
  measured_product_count,
  spend,
  conversion_value,
  conversions,
  clicks,
  impressions,
  SAFE_DIVIDE(conversion_value, spend) AS roas,
  SAFE_DIVIDE(conversions, clicks) AS cvr,
  SAFE_DIVIDE(spend, clicks) AS cpc,
  SAFE_DIVIDE(conversion_value, conversions) AS aov
FROM product_baseline_total;

-- ============================================================
-- 03. DAILY CAMPAIGN PERFORMANCE
-- Purpose:
--   Inspect trend and avoid treating a single short period as the
--   whole account story.
-- ============================================================

SELECT
  segments_date AS performance_date,
  SUM(metrics_cost_micros) / 1000000 AS spend,
  SUM(metrics_conversions_value) AS conversion_value,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_impressions) AS impressions,
  SAFE_DIVIDE(
    SUM(metrics_conversions_value),
    SUM(metrics_cost_micros) / 1000000
  ) AS roas
FROM `quantacusinterviewproject.interview_ayad.p_ads_Campaignbasicstats`
WHERE segments_date BETWEEN baseline_start AND baseline_end
GROUP BY performance_date
ORDER BY performance_date;

-- ============================================================
-- 04. MONTHLY CAMPAIGN PERFORMANCE
-- Purpose:
--   Show the longer-term context behind the latest 30-day window.
-- ============================================================

SELECT
  DATE_TRUNC(segments_date, MONTH) AS performance_month,
  SUM(metrics_cost_micros) / 1000000 AS spend,
  SUM(metrics_conversions_value) AS conversion_value,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_impressions) AS impressions,
  SAFE_DIVIDE(
    SUM(metrics_conversions_value),
    SUM(metrics_cost_micros) / 1000000
  ) AS roas
FROM `quantacusinterviewproject.interview_ayad.p_ads_Campaignbasicstats`
GROUP BY performance_month
ORDER BY performance_month;

-- ============================================================
-- 05. CAMPAIGN PERFORMANCE
-- Purpose:
--   Rank campaigns by economic contribution, not ROAS alone.
--   Spend and value shares show where changes can matter.
-- ============================================================

WITH campaign_performance AS (
  SELECT
    campaign_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks,
    SUM(metrics_impressions) AS impressions
  FROM `quantacusinterviewproject.interview_ayad.p_ads_Campaignbasicstats`
  WHERE segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY campaign_id
  HAVING SUM(metrics_cost_micros) > 0
)
SELECT
  campaign_id,
  spend,
  conversion_value,
  conversions,
  clicks,
  impressions,
  SAFE_DIVIDE(conversion_value, spend) AS roas,
  SAFE_DIVIDE(conversions, clicks) AS cvr,
  SAFE_DIVIDE(spend, clicks) AS cpc,
  SAFE_DIVIDE(conversion_value, conversions) AS aov,
  SAFE_DIVIDE(
    spend,
    SUM(spend) OVER ()
  ) AS spend_share,
  SAFE_DIVIDE(
    conversion_value,
    SUM(conversion_value) OVER ()
  ) AS value_share
FROM campaign_performance
ORDER BY spend DESC;

-- ============================================================
-- 06. FOCUS CAMPAIGN CONFIGURATION
-- Purpose:
--   Verify the campaign structure before making bidding claims.
--   The supplied table contains multiple configuration rows per
--   campaign. Do NOT infer historical sequence from row order.
-- ============================================================

SELECT DISTINCT
  campaign_id,
  bidding_strategy_name,
  campaign_bidding_strategy,
  campaign_bidding_strategy_type,
  campaign_budget_amount_micros,
  campaign_budget_explicitly_shared,
  campaign_budget_has_recommended_budget,
  campaign_budget_period,
  campaign_budget_recommended_budget_amount_micros,
  campaign_budget_total_amount_micros,
  campaign_campaign_budget,
  campaign_experiment_type,
  campaign_manual_cpc_enhanced_cpc_enabled,
  campaign_maximize_conversion_value_target_roas,
  campaign_percent_cpc_enhanced_cpc_enabled,
  campaign_start_date_time,
  campaign_status,
  campaign_serving_status,
  campaign_name
FROM `quantacusinterviewproject.interview_ayad.p_ads_Campaign`
WHERE campaign_id = focus_campaign_id
ORDER BY campaign_budget_amount_micros;

-- ============================================================
-- 07. FOCUS CAMPAIGN — CATEGORY PERFORMANCE
-- Purpose:
--   Determine whether campaign weakness is concentrated in a
--   category or spread across major categories.
-- ============================================================

SELECT
  segments_product_type_l1 AS product_category,
  SUM(metrics_cost_micros) / 1000000 AS spend,
  SUM(metrics_conversions_value) AS conversion_value,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_impressions) AS impressions,
  SAFE_DIVIDE(
    SUM(metrics_conversions_value),
    SUM(metrics_cost_micros) / 1000000
  ) AS roas,
  SAFE_DIVIDE(
    SUM(metrics_conversions),
    SUM(metrics_clicks)
  ) AS cvr,
  SAFE_DIVIDE(
    SUM(metrics_cost_micros) / 1000000,
    SUM(metrics_clicks)
  ) AS cpc,
  SAFE_DIVIDE(
    SUM(metrics_conversions_value),
    SUM(metrics_conversions)
  ) AS aov
FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
WHERE campaign_id = focus_campaign_id
  AND segments_date BETWEEN baseline_start AND baseline_end
GROUP BY product_category
HAVING SUM(metrics_cost_micros) > 0
ORDER BY spend DESC;

-- ============================================================
-- 08. FOCUS CAMPAIGN — PRODUCT PERFORMANCE
-- Purpose:
--   Full product-level allocation view. This is the source for
--   evidence-based product segmentation.
-- ============================================================

WITH product_performance AS (
  SELECT
    segments_product_item_id AS product_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks,
    SUM(metrics_impressions) AS impressions
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id
  HAVING SUM(metrics_cost_micros) > 0
)
SELECT
  product_id,
  spend,
  conversion_value,
  conversions,
  clicks,
  impressions,
  SAFE_DIVIDE(conversion_value, spend) AS roas,
  SAFE_DIVIDE(conversions, clicks) AS cvr,
  SAFE_DIVIDE(spend, clicks) AS cpc,
  SAFE_DIVIDE(conversion_value, conversions) AS aov,
  SAFE_DIVIDE(spend, SUM(spend) OVER ()) AS spend_share,
  SAFE_DIVIDE(conversion_value, SUM(conversion_value) OVER ()) AS value_share
FROM product_performance
ORDER BY spend DESC;

-- ============================================================
-- 09. FOCUS CAMPAIGN — FUNNEL DIAGNOSTICS
-- Purpose:
--   Explain why products differ. ROAS is not diagnosed by CTR alone.
--   Compare CTR, CPC, CVR and AOV alongside ROAS.
-- ============================================================

WITH product_funnel AS (
  SELECT
    segments_product_item_id AS product_id,
    SUM(metrics_impressions) AS impressions,
    SUM(metrics_clicks) AS clicks,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_conversions_value) AS conversion_value
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id
  HAVING SUM(metrics_cost_micros) > 0
)
SELECT
  product_id,
  impressions,
  clicks,
  SAFE_DIVIDE(clicks, impressions) AS ctr,
  spend,
  SAFE_DIVIDE(spend, clicks) AS cpc,
  conversions,
  SAFE_DIVIDE(conversions, clicks) AS cvr,
  SAFE_DIVIDE(conversion_value, conversions) AS aov,
  conversion_value,
  SAFE_DIVIDE(conversion_value, spend) AS roas
FROM product_funnel
ORDER BY roas DESC;

-- ============================================================
-- 10. FOCUS CAMPAIGN — FIRST HALF VS SECOND HALF STABILITY
-- Purpose:
--   Separate persistent weakness from temporary deterioration or
--   improvement. Do not make decisions on one short window alone.
-- ============================================================

WITH product_half_period AS (
  SELECT
    segments_product_item_id AS product_id,
    CASE
      WHEN segments_date BETWEEN baseline_start
                             AND DATE_ADD(baseline_start, INTERVAL 14 DAY)
        THEN 'FIRST_15_DAYS'
      WHEN segments_date BETWEEN DATE_ADD(baseline_start, INTERVAL 15 DAY)
                             AND baseline_end
        THEN 'LAST_15_DAYS'
      ELSE NULL
    END AS period_group,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id, period_group
)
SELECT
  product_id,
  period_group,
  spend,
  conversion_value,
  conversions,
  clicks,
  SAFE_DIVIDE(conversion_value, spend) AS roas,
  SAFE_DIVIDE(conversions, clicks) AS cvr,
  SAFE_DIVIDE(spend, clicks) AS cpc,
  SAFE_DIVIDE(conversion_value, conversions) AS aov
FROM product_half_period
WHERE period_group IS NOT NULL
ORDER BY product_id, period_group;

-- ============================================================
-- 11. PRODUCT ROAS BANDS — ALLOCATION EVIDENCE
-- Purpose:
--   Quantify the share of spend/value in each ROAS band.
--   This is a portfolio-level signal, not a product pause list.
-- ============================================================

WITH product_performance AS (
  SELECT
    segments_product_item_id AS product_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id
  HAVING SUM(metrics_cost_micros) > 0
),
product_bands AS (
  SELECT
    product_id,
    spend,
    conversion_value,
    conversions,
    SAFE_DIVIDE(conversion_value, spend) AS roas,
    CASE
      WHEN SAFE_DIVIDE(conversion_value, spend) < 2 THEN '<2x'
      WHEN SAFE_DIVIDE(conversion_value, spend) < 3 THEN '2x–<3x'
      WHEN SAFE_DIVIDE(conversion_value, spend) < 4 THEN '3x–<4x'
      WHEN SAFE_DIVIDE(conversion_value, spend) < 5 THEN '4x–<5x'
      ELSE '5x+'
    END AS roas_band
  FROM product_performance
)
SELECT
  roas_band,
  COUNT(*) AS product_count,
  SUM(spend) AS spend,
  SAFE_DIVIDE(SUM(spend), SUM(SUM(spend)) OVER ()) AS spend_share,
  SUM(conversion_value) AS conversion_value,
  SAFE_DIVIDE(
    SUM(conversion_value),
    SUM(SUM(conversion_value)) OVER ()
  ) AS value_share,
  SAFE_DIVIDE(SUM(conversion_value), SUM(spend)) AS band_roas,
  SUM(conversions) AS conversions
FROM product_bands
GROUP BY roas_band
ORDER BY
  CASE roas_band
    WHEN '<2x' THEN 1
    WHEN '2x–<3x' THEN 2
    WHEN '3x–<4x' THEN 3
    WHEN '4x–<5x' THEN 4
    WHEN '5x+' THEN 5
  END;

-- ============================================================
-- 12. COMMERCIALLY MEANINGFUL LOW-ROAS PRODUCTS
-- Purpose:
--   Prevent the <2x band from being interpreted as thousands of
--   automatic pause decisions. Apply an explicit spend threshold.
--   Adjust the threshold during client review if required.
-- ============================================================

WITH product_performance AS (
  SELECT
    segments_product_item_id AS product_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id
  HAVING SUM(metrics_cost_micros) > 0
)
SELECT
  product_id,
  spend,
  conversion_value,
  conversions,
  clicks,
  SAFE_DIVIDE(conversion_value, spend) AS roas,
  SAFE_DIVIDE(conversions, clicks) AS cvr,
  SAFE_DIVIDE(spend, clicks) AS cpc,
  SAFE_DIVIDE(conversion_value, conversions) AS aov
FROM product_performance
WHERE spend >= meaningful_spend_threshold
  AND SAFE_DIVIDE(conversion_value, spend) < 2
ORDER BY spend DESC;

-- ============================================================
-- 13. HIGH-CONFIDENCE PRODUCT EXAMPLES
-- Purpose:
--   Provide candidate products for Protect & Scale / Limit & Pause
--   discussions. This is a diagnostic list, not an automatic action.
-- ============================================================

WITH product_performance AS (
  SELECT
    segments_product_item_id AS product_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks,
    COUNT(DISTINCT segments_date) AS active_days
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id
  HAVING SUM(metrics_cost_micros) > 0
)
SELECT
  product_id,
  spend,
  conversion_value,
  conversions,
  clicks,
  active_days,
  SAFE_DIVIDE(conversion_value, spend) AS roas,
  CASE
    WHEN spend >= 1000
      AND conversions >= 5
      AND SAFE_DIVIDE(conversion_value, spend) >= 5
      AND active_days >= 20
      THEN 'PROTECT_AND_SCALE'
    WHEN spend >= 1000
      AND conversions >= 5
      AND SAFE_DIVIDE(conversion_value, spend) < 2
      AND active_days >= 20
      THEN 'LIMIT_OR_PAUSE_REVIEW'
    WHEN spend >= 1000
      AND conversions >= 5
      AND SAFE_DIVIDE(conversion_value, spend) < 5
      THEN 'FIX_AND_RETEST_REVIEW'
    ELSE 'INSUFFICIENT_EVIDENCE'
  END AS decision_group
FROM product_performance
ORDER BY
  CASE
    WHEN spend >= 1000
      AND conversions >= 5
      AND SAFE_DIVIDE(conversion_value, spend) >= 5
      AND active_days >= 20 THEN 1
    WHEN spend >= 1000
      AND conversions >= 5
      AND SAFE_DIVIDE(conversion_value, spend) < 2
      AND active_days >= 20 THEN 2
    WHEN spend >= 1000
      AND conversions >= 5
      AND SAFE_DIVIDE(conversion_value, spend) < 5 THEN 3
    ELSE 4
  END,
  spend DESC;

-- ============================================================
-- 14. LATEST CATALOGUE SNAPSHOT
-- Purpose:
--   Deduplicate the historical Products table before joining.
--   One latest row per normalized offer_id is used for diagnostic
--   catalogue attributes.
-- ============================================================

WITH latest_catalogue AS (
  SELECT
    LOWER(offer_id) AS normalized_offer_id,
    offer_id,
    product_id,
    product_data_timestamp,
    _PARTITIONTIME AS partition_time,
    title,
    availability,
    brand,
    color,
    item_group_id,
    price,
    sale_price,
    product_type_l1,
    product_type_l2,
    product_type_l3,
    issues,
    ROW_NUMBER() OVER (
      PARTITION BY LOWER(offer_id)
      ORDER BY product_data_timestamp DESC, _PARTITIONTIME DESC
    ) AS row_rank
  FROM `quantacusinterviewproject.interview_ayad.Products`
  WHERE offer_id IS NOT NULL
)
SELECT
  normalized_offer_id,
  offer_id,
  product_id,
  product_data_timestamp,
  partition_time,
  title,
  availability,
  brand,
  color,
  item_group_id,
  price,
  sale_price,
  product_type_l1,
  product_type_l2,
  product_type_l3,
  issues
FROM latest_catalogue
WHERE row_rank = 1;

-- ============================================================
-- 15. PRODUCT-TO-CATALOGUE LINKAGE COVERAGE
-- Purpose:
--   Validate the working mapping between ShoppingProductStats
--   segments_product_item_id and Products.offer_id.
-- ============================================================

WITH performance_products AS (
  SELECT DISTINCT
    LOWER(segments_product_item_id) AS normalized_product_id
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
    AND segments_product_item_id IS NOT NULL
),
latest_catalogue_ids AS (
  SELECT DISTINCT
    LOWER(offer_id) AS normalized_offer_id
  FROM `quantacusinterviewproject.interview_ayad.Products`
  WHERE offer_id IS NOT NULL
)
SELECT
  COUNT(*) AS performance_product_ids,
  COUNTIF(c.normalized_offer_id IS NOT NULL) AS matched_product_ids,
  COUNTIF(c.normalized_offer_id IS NULL) AS unmatched_product_ids,
  SAFE_DIVIDE(
    COUNTIF(c.normalized_offer_id IS NOT NULL),
    COUNT(*)
  ) AS match_rate
FROM performance_products p
LEFT JOIN latest_catalogue_ids c
  ON p.normalized_product_id = c.normalized_offer_id;

-- ============================================================
-- 16. SELECTED PRODUCT CATALOGUE + PERFORMANCE
-- Purpose:
--   Join performance to the latest catalogue snapshot without
--   multiplying performance rows.
-- ============================================================

WITH product_performance AS (
  SELECT
    segments_product_item_id AS product_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks,
    COUNT(DISTINCT segments_date) AS active_days
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY product_id
  HAVING SUM(metrics_cost_micros) > 0
),
latest_catalogue AS (
  SELECT
    LOWER(offer_id) AS normalized_offer_id,
    offer_id,
    title,
    availability,
    price,
    sale_price,
    product_type_l1,
    product_type_l2,
    product_type_l3,
    issues,
    ROW_NUMBER() OVER (
      PARTITION BY LOWER(offer_id)
      ORDER BY product_data_timestamp DESC, _PARTITIONTIME DESC
    ) AS row_rank
  FROM `quantacusinterviewproject.interview_ayad.Products`
  WHERE offer_id IS NOT NULL
)
SELECT
  p.product_id,
  c.offer_id,
  c.title,
  c.availability,
  c.price,
  c.sale_price,
  c.product_type_l1,
  c.product_type_l2,
  c.product_type_l3,
  p.spend,
  p.conversion_value,
  p.conversions,
  p.clicks,
  p.active_days,
  SAFE_DIVIDE(p.conversion_value, p.spend) AS roas,
  c.issues
FROM product_performance p
LEFT JOIN latest_catalogue c
  ON LOWER(p.product_id) = c.normalized_offer_id
 AND c.row_rank = 1
WHERE p.spend >= 1000
  AND (
    SAFE_DIVIDE(p.conversion_value, p.spend) < 2
    OR SAFE_DIVIDE(p.conversion_value, p.spend) >= 5
  )
ORDER BY p.spend DESC;

-- ============================================================
-- 17. LATEST CATALOGUE ISSUE TYPES
-- Purpose:
--   Identify current feed/catalogue issues for products in the
--   focus campaign. Historical rows are excluded from this view.
-- ============================================================

WITH latest_catalogue AS (
  SELECT
    LOWER(offer_id) AS normalized_offer_id,
    offer_id,
    title,
    availability,
    issues,
    ROW_NUMBER() OVER (
      PARTITION BY LOWER(offer_id)
      ORDER BY product_data_timestamp DESC, _PARTITIONTIME DESC
    ) AS row_rank
  FROM `quantacusinterviewproject.interview_ayad.Products`
  WHERE offer_id IS NOT NULL
),
focus_products AS (
  SELECT DISTINCT
    LOWER(segments_product_item_id) AS normalized_product_id
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
)
SELECT
  c.offer_id,
  c.title,
  c.availability,
  issue.code AS issue_code,
  issue.servability,
  issue.resolution,
  issue.attribute_name,
  issue.destination,
  issue.short_description,
  issue.detailed_description
FROM latest_catalogue c
JOIN focus_products p
  ON c.normalized_offer_id = p.normalized_product_id
LEFT JOIN UNNEST(c.issues) AS issue
WHERE c.row_rank = 1
  AND issue.code IS NOT NULL
ORDER BY c.offer_id, issue.code;

-- ============================================================
-- 18. HISTORICAL PRODUCT AVAILABILITY
-- Purpose:
--   Availability is a product-specific operational signal.
--   This query measures how often catalogue snapshots show
--   IN_STOCK / OUT_OF_STOCK during the analysis window.
--   It does NOT claim that an OOS snapshot caused spend.
-- ============================================================

WITH focus_products AS (
  SELECT DISTINCT
    LOWER(segments_product_item_id) AS normalized_product_id
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
),
catalogue_daily AS (
  SELECT
    LOWER(offer_id) AS normalized_offer_id,
    DATE(product_data_timestamp) AS catalogue_date,
    availability,
    ROW_NUMBER() OVER (
      PARTITION BY LOWER(offer_id), DATE(product_data_timestamp)
      ORDER BY product_data_timestamp DESC, _PARTITIONTIME DESC
    ) AS row_rank
  FROM `quantacusinterviewproject.interview_ayad.Products`
  WHERE offer_id IS NOT NULL
    AND DATE(product_data_timestamp) BETWEEN baseline_start AND baseline_end
)
SELECT
  c.normalized_offer_id AS product_id,
  COUNTIF(c.availability = 'IN_STOCK') AS in_stock_days,
  COUNTIF(c.availability = 'OUT_OF_STOCK') AS out_of_stock_days,
  COUNT(*) AS catalogue_snapshot_days,
  SAFE_DIVIDE(
    COUNTIF(c.availability = 'OUT_OF_STOCK'),
    COUNT(*)
  ) AS out_of_stock_share
FROM catalogue_daily c
JOIN focus_products p
  ON c.normalized_offer_id = p.normalized_product_id
WHERE c.row_rank = 1
GROUP BY product_id
ORDER BY out_of_stock_share DESC;

-- ============================================================
-- 19. DAILY PRODUCT PERFORMANCE + AVAILABILITY
-- Purpose:
--   Pair daily product performance with an as-of catalogue snapshot.
--   NO_CATALOGUE_SNAPSHOT is intentionally distinct from OOS.
-- ============================================================

WITH daily_product_performance AS (
  SELECT
    segments_date AS performance_date,
    LOWER(segments_product_item_id) AS normalized_product_id,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value,
    SUM(metrics_conversions) AS conversions,
    SUM(metrics_clicks) AS clicks
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE campaign_id = focus_campaign_id
    AND segments_date BETWEEN baseline_start AND baseline_end
  GROUP BY performance_date, normalized_product_id
  HAVING SUM(metrics_cost_micros) > 0
),
catalogue_daily AS (
  SELECT
    LOWER(offer_id) AS normalized_offer_id,
    DATE(product_data_timestamp) AS catalogue_date,
    availability,
    ROW_NUMBER() OVER (
      PARTITION BY LOWER(offer_id), DATE(product_data_timestamp)
      ORDER BY product_data_timestamp DESC, _PARTITIONTIME DESC
    ) AS row_rank
  FROM `quantacusinterviewproject.interview_ayad.Products`
  WHERE offer_id IS NOT NULL
    AND DATE(product_data_timestamp) BETWEEN baseline_start AND baseline_end
)
SELECT
  p.performance_date,
  p.normalized_product_id AS product_id,
  p.spend,
  p.conversion_value,
  p.conversions,
  p.clicks,
  SAFE_DIVIDE(p.conversion_value, p.spend) AS roas,
  COALESCE(
    c.availability,
    'NO_CATALOGUE_SNAPSHOT'
  ) AS catalogue_availability
FROM daily_product_performance p
LEFT JOIN catalogue_daily c
  ON p.normalized_product_id = c.normalized_offer_id
 AND p.performance_date = c.catalogue_date
 AND c.row_rank = 1
ORDER BY p.normalized_product_id, p.performance_date;

-- ============================================================
-- 20. 5x GAP-CLOSURE MATH
-- Purpose:
--   Quantify the conversion-value lift required to move the two
--   measured baselines to 5x at constant spend.
--   These are mathematical scenarios, NOT forecasts.
-- ============================================================

WITH measured_baselines AS (
  SELECT
    'CAMPAIGN_LEVEL' AS baseline_type,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value
  FROM `quantacusinterviewproject.interview_ayad.p_ads_Campaignbasicstats`
  WHERE segments_date BETWEEN baseline_start AND baseline_end

  UNION ALL

  SELECT
    'PRODUCT_LEVEL' AS baseline_type,
    SUM(metrics_cost_micros) / 1000000 AS spend,
    SUM(metrics_conversions_value) AS conversion_value
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE segments_date BETWEEN baseline_start AND baseline_end
)
SELECT
  baseline_type,
  spend,
  conversion_value,
  SAFE_DIVIDE(conversion_value, spend) AS current_roas,
  5.0 AS target_roas,
  (5.0 * spend) - conversion_value AS incremental_value_required,
  SAFE_DIVIDE(
    (5.0 * spend) - conversion_value,
    conversion_value
  ) AS required_value_lift_pct
FROM measured_baselines
ORDER BY baseline_type;

-- ============================================================
-- 21. EXPERIMENT SCORECARD TEMPLATE
-- Purpose:
--   Produce a consistent control/treatment scorecard after the
--   live test is implemented. The supplied dataset does not
--   contain treatment/control labels, so this query is a template.
-- ============================================================

-- Replace the placeholder experiment labels only after the live
-- account test has been implemented and labelled in the source.
--
-- Expected output fields:
--   experiment_group
--   spend
--   conversion_value
--   conversions
--   roas
--   cvr
--   cpc
--   aov
--
-- Example structure:
--
-- WITH experiment_performance AS (
--   SELECT
--     experiment_group,
--     SUM(spend) AS spend,
--     SUM(conversion_value) AS conversion_value,
--     SUM(conversions) AS conversions,
--     SUM(clicks) AS clicks
--   FROM <approved_experiment_source>
--   WHERE performance_date BETWEEN baseline_start AND baseline_end
--   GROUP BY experiment_group
-- )
-- SELECT
--   experiment_group,
--   spend,
--   conversion_value,
--   conversions,
--   SAFE_DIVIDE(conversion_value, spend) AS roas,
--   SAFE_DIVIDE(conversions, clicks) AS cvr,
--   SAFE_DIVIDE(spend, clicks) AS cpc,
--   SAFE_DIVIDE(conversion_value, conversions) AS aov
-- FROM experiment_performance;

-- ============================================================
-- 22. VALIDATION CHECKS
-- Purpose:
--   Basic data-quality checks to run before trusting the analysis.
-- ============================================================

-- 22A. Null/zero spend and conversion-value checks.
SELECT
  COUNT(*) AS total_rows,
  COUNTIF(metrics_cost_micros IS NULL) AS null_cost_rows,
  COUNTIF(metrics_conversions_value IS NULL) AS null_value_rows,
  COUNTIF(metrics_cost_micros < 0) AS negative_cost_rows,
  COUNTIF(metrics_conversions_value < 0) AS negative_value_rows
FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
WHERE segments_date BETWEEN baseline_start AND baseline_end;

-- 22B. Date coverage check.
SELECT
  MIN(segments_date) AS earliest_date,
  MAX(segments_date) AS latest_date,
  COUNT(DISTINCT segments_date) AS distinct_dates
FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
WHERE segments_date BETWEEN baseline_start AND baseline_end;

-- 22C. Campaign/product population comparison.
WITH campaign_population AS (
  SELECT
    SUM(metrics_cost_micros) / 1000000 AS campaign_spend,
    SUM(metrics_conversions_value) AS campaign_value
  FROM `quantacusinterviewproject.interview_ayad.p_ads_Campaignbasicstats`
  WHERE segments_date BETWEEN baseline_start AND baseline_end
),
product_population AS (
  SELECT
    SUM(metrics_cost_micros) / 1000000 AS product_spend,
    SUM(metrics_conversions_value) AS product_value
  FROM `quantacusinterviewproject.interview_ayad.p_ads_ShoppingProductStats`
  WHERE segments_date BETWEEN baseline_start AND baseline_end
)
SELECT
  campaign_spend,
  product_spend,
  SAFE_DIVIDE(product_spend, campaign_spend) AS product_to_campaign_spend_ratio,
  campaign_value,
  product_value,
  SAFE_DIVIDE(product_value, campaign_value) AS product_to_campaign_value_ratio
FROM campaign_population
CROSS JOIN product_population;

-- ============================================================
-- 23. RECOMMENDED DECISION RULES — DOCUMENTATION ONLY
-- Purpose:
--   Keep the implementation rules explicit and auditable.
--   These are business rules for review, not automatic account
--   changes.
-- ============================================================

-- PROTECT & SCALE:
--   Meaningful spend + sufficient conversions + mature observation
--   + ROAS >= 5x + stable/improving + in stock + no critical issue.
--
-- FIX & RETEST:
--   Meaningful spend + sufficient evidence + ROAS < 5x + plausible
--   product/funnel/feed intervention.
--
-- LIMIT / PAUSE REVIEW:
--   Meaningful spend + persistent ROAS < 2x + sufficient evidence
--   + mature observation + no strategic/business exception.
--
-- INSUFFICIENT EVIDENCE:
--   Low spend OR low conversions OR recent launch OR unstable data.
--
-- ROLLBACK:
--   Reverse a material treatment/allocation/bidding change when an
--   approved revenue, spend, conversion or learning guardrail is
--   breached.
--
-- IMPORTANT:
--   These rules must be calibrated with the client before automated
--   execution. They are intentionally conservative and do not claim
--   that every product below 5x should be paused.
