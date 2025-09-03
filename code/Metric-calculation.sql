# ==== A/B 테스트 시각화용 상세 데이터 (1일, 7일, 14일, 30일 기간별) ####
WITH
periods AS (
    SELECT unnest(ARRAY[1, 7, 14, 30]) AS period_days
),
view_min_time AS (
    SELECT 
        visitorid, 
        categoryid,
        itemid,
        MIN(date_only) AS view_min_time,
        ab_group 
    FROM total_retailrocket_data2
    WHERE event = 'view' AND ab_group IS NOT NULL 
    GROUP BY visitorid, categoryid, itemid, ab_group
), 
transaction_min_time AS (
    SELECT 
        visitorid, 
        categoryid,
        itemid,
        MIN(date_only) AS transaction_min_time,
        ab_group 
    FROM total_retailrocket_data2
    WHERE event = 'transaction' AND ab_group IS NOT NULL 
    GROUP BY visitorid, categoryid, itemid, ab_group
),
cvr_data AS (
    SELECT 
        p.period_days,
        v.ab_group,
        v.categoryid,
        v.itemid,
        COUNT(*) AS total_users,
        SUM(
            CASE 
                WHEN t.transaction_min_time IS NOT NULL 
                     AND t.transaction_min_time::date - v.view_min_time::date <= p.period_days
                     AND t.transaction_min_time::date >= v.view_min_time::date  
                THEN 1 ELSE 0 
            END
        ) AS converted_users
    FROM view_min_time v 
    CROSS JOIN periods p
    LEFT JOIN transaction_min_time t ON v.visitorid = t.visitorid 
                                     AND v.categoryid = t.categoryid
                                     AND v.itemid = t.itemid
    GROUP BY p.period_days, v.ab_group, v.categoryid, v.itemid
),
avg_time_transaction AS (
    SELECT         
        v.ab_group,
        v.categoryid,
        v.itemid,
        AVG(t.transaction_min_time::date - v.view_min_time::date) AS avg_time_transaction
    FROM view_min_time v 
    LEFT JOIN transaction_min_time t ON v.visitorid = t.visitorid 
                                     AND v.categoryid = t.categoryid
                                     AND v.itemid = t.itemid
    WHERE t.transaction_min_time IS NOT NULL AND t.transaction_min_time::date >= v.view_min_time::date
    GROUP BY v.ab_group, v.categoryid, v.itemid  
),
path_base AS (
    SELECT 
        visitorid,
        categoryid,
        itemid,
        event,
        MIN(date_only) AS min_time,
        ab_group
    FROM total_retailrocket_data2
    WHERE ab_group IS NOT NULL
    GROUP BY visitorid, categoryid, itemid, event, ab_group
),
period_events AS (
    SELECT 
        p.period_days,
        a.visitorid,
        a.categoryid,
        a.itemid,
        a.event,
        a.min_time,
        a.ab_group 
    FROM path_base a 
    CROSS JOIN periods p
    JOIN path_base b ON a.visitorid = b.visitorid 
                     AND a.categoryid = b.categoryid
                     AND a.itemid = b.itemid 
                     AND b.event = 'view'
                     AND a.min_time::date >= b.min_time::date 
                     AND a.min_time::date < b.min_time::date + (p.period_days || ' days')::INTERVAL
),
step_times AS (
    SELECT
        period_days,
        visitorid, 
        categoryid,
        itemid, 
        ab_group,
        MIN(CASE WHEN event = 'view' THEN min_time END) AS t_view,
        MIN(CASE WHEN event IN ('addtocart', 'cart') THEN min_time END) AS t_cart,
        MIN(CASE WHEN event = 'transaction' THEN min_time END) AS t_purchase
    FROM period_events
    GROUP BY period_days, visitorid, categoryid, itemid, ab_group
),
funnel_detail AS (
    SELECT
        period_days,
        ab_group,
        categoryid,
        itemid,
        -- View to Cart 전환
        SUM(
            CASE WHEN t_view IS NOT NULL AND t_cart IS NOT NULL AND t_cart >= t_view 
            THEN 1 ELSE 0 END
        ) AS view_to_cart_numerator,
        COUNT(*) FILTER (WHERE t_view IS NOT NULL) AS view_to_cart_denominator,
        -- Cart to Purchase 전환
        SUM(
            CASE WHEN t_cart IS NOT NULL AND t_purchase IS NOT NULL AND t_purchase >= t_cart 
            THEN 1 ELSE 0 END
        ) AS cart_to_purchase_numerator,
        COUNT(*) FILTER (WHERE t_cart IS NOT NULL) AS cart_to_purchase_denominator
    FROM step_times
    GROUP BY period_days, ab_group, categoryid, itemid
),
purchase_path AS (
    SELECT 
        period_days,
        visitorid,
        categoryid,
        itemid,
        ab_group,
        CASE 
            WHEN BOOL_OR(event = 'addtocart') AND BOOL_OR(event = 'transaction') THEN 'via_cart'
            WHEN NOT BOOL_OR(event = 'addtocart') AND BOOL_OR(event = 'transaction') THEN 'direct'
            ELSE 'no_purchase' 
        END AS path_type
    FROM period_events 
    GROUP BY period_days, visitorid, categoryid, itemid, ab_group
),
path_detail AS (
    SELECT
        period_days,
        ab_group,
        categoryid,
        itemid,
        SUM(CASE WHEN path_type = 'direct' THEN 1 ELSE 0 END) AS direct_numerator,
        SUM(CASE WHEN path_type = 'via_cart' THEN 1 ELSE 0 END) AS via_cart_numerator,
        COUNT(*) FILTER (WHERE path_type IN ('direct', 'via_cart')) AS total_purchases
    FROM purchase_path
    GROUP BY period_days, ab_group, categoryid, itemid
)
SELECT 
    c.period_days AS "기간",
    c.ab_group AS "AB그룹",
    c.categoryid AS "카테고리ID",
    SUM(c.converted_users) AS "구매자수",
    SUM(c.total_users) AS "총뷰수",
    CASE WHEN SUM(c.total_users) > 0 THEN ROUND(SUM(c.converted_users)::numeric / SUM(c.total_users), 4) ELSE 0 END AS "전환율",
    AVG(COALESCE(a.avg_time_transaction, 0)) AS "평균구매소요일수",
    SUM(f.view_to_cart_numerator) AS "뷰투카트전환자수",
    SUM(f.view_to_cart_denominator) AS "총뷰수_퍼널",
    CASE WHEN SUM(f.view_to_cart_denominator) > 0 THEN ROUND(SUM(f.view_to_cart_numerator)::numeric / SUM(f.view_to_cart_denominator), 4) ELSE 0 END AS "뷰투카트전환율",
    SUM(f.cart_to_purchase_numerator) AS "카트투구매전환자수",
    SUM(f.cart_to_purchase_denominator) AS "총카트수",
    CASE WHEN SUM(f.cart_to_purchase_denominator) > 0 THEN ROUND(SUM(f.cart_to_purchase_numerator)::numeric / SUM(f.cart_to_purchase_denominator), 4) ELSE 0 END AS "카트투구매전환율",
    SUM(p.direct_numerator) AS "직접구매수",
    SUM(p.via_cart_numerator) AS "카트경유구매수",
    SUM(p.total_purchases) AS "총구매수",
    CASE WHEN SUM(p.total_purchases) > 0 THEN ROUND(SUM(p.direct_numerator)::numeric / SUM(p.total_purchases), 4) ELSE 0 END AS "직접구매비율",
    CASE WHEN SUM(p.total_purchases) > 0 THEN ROUND(SUM(p.via_cart_numerator)::numeric / SUM(p.total_purchases), 4) ELSE 0 END AS "카트경유구매비율"
FROM cvr_data c
LEFT JOIN avg_time_transaction a ON c.ab_group = a.ab_group 
                                  AND c.categoryid = a.categoryid 
                                  AND c.itemid = a.itemid
LEFT JOIN funnel_detail f ON c.period_days = f.period_days 
                           AND c.ab_group = f.ab_group 
                           AND c.categoryid = f.categoryid 
                           AND c.itemid = f.itemid
LEFT JOIN path_detail p ON c.period_days = p.period_days 
                        AND c.ab_group = p.ab_group 
                        AND c.categoryid = p.categoryid 
                        AND c.itemid = p.itemid
GROUP BY c.period_days, c.ab_group, c.categoryid
ORDER BY c.period_days, c.ab_group, c.categoryid;
