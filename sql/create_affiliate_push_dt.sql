create or replace dynamic table DW_CP.PUBLIC.GGVEGAS_AFFILIATE_PUSH(
    AGGREGATED_AT,
    NETWORK,
    BRAND_ID,
    GP_ID,
    NICKNAME,
    PLAYER_ID,
    MARKETING_TYPE,
    AFFILIATECLICKID,
    AFFILIATESITEID,
    AFFILIATEMEMBERID,
    REGISTRATIONTYPE,
    KYCSTATUS,
    REGISTRATION_DATE,
    REGISTRATIONS,
    TIMEONDEVICEMIN,
    SESSIONSPLAYED,
    BET,
    PAIDOUTWIN,
    BET_COUNT,
    WON_GAME_COUNT,
    GGR,
    THEO_WIN,
    ESTIMATED_GGR,
    FIRST_DEPOSIT_AMOUNT,
    FIRST_DEPOSIT_COUNT,
    TOTAL_DEPOSIT_COUNT,
    TOTAL_DEPOSIT_AMOUNT,
    TOTAL_WITHDRAWAL_AMOUNT
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_SCHEDULE warehouse = DT_CP_WH
 as

/* 1. Calculate Hold % for Theo Win */
WITH RTP_Data AS (
    SELECT
        DISTINCT aggregated_at AS GamingDate,
        BRAND_ID,
        BRAND_NAME,
        SITE_ID,
        PROVIDER_CODE,
        PROVIDER_NAME,
        CATEGORY_CODE,
        game_name,
        game_code,
        game_rtp,
        1 - game_rtp AS HoldPerc
    FROM DW_WAREHOUSE.PUBLIC.CP_STATS_PERIODIC_DAILY
    WHERE aggregated_at >= '2025-01-01'
),

/* 2. Aggregate transactions by User and Day */
Daily_Transaction_Stats AS (
    SELECT
        DATE_TRUNC('day', PT.CREATED_AT) AS TransactionDate,
        PT.GP_ID,
        PT.BRAND_ID,
        MAX(CASE
            WHEN PT.IS_FIRST_DEPOSIT = TRUE AND PT.TYPE_STRING = 'Deposit' AND PT.STATUS_STRING = 'Completed'
            THEN PT.AMOUNT_IN_USD ELSE 0 END) AS FIRST_DEPOSIT_AMOUNT,
        SUM(CASE 
            WHEN PT.IS_FIRST_DEPOSIT = TRUE AND PT.TYPE_STRING = 'Deposit' AND PT.STATUS_STRING = 'Completed' 
            THEN 1 ELSE 0 END) AS FIRST_DEPOSIT_COUNT,
        SUM(CASE
            WHEN PT.TYPE_STRING = 'Deposit' AND PT.STATUS_STRING = 'Completed'
            THEN PT.AMOUNT_IN_USD ELSE 0 END) AS TOTAL_DEPOSIT_AMOUNT,
        SUM(CASE 
            WHEN PT.TYPE_STRING = 'Deposit' AND PT.STATUS_STRING = 'Completed' 
            THEN 1 ELSE 0 END) AS TOTAL_DEPOSIT_COUNT,
        SUM(CASE
            WHEN PT.TYPE_STRING = 'Withdrawal' AND PT.STATUS_STRING = 'Completed'
            THEN PT.AMOUNT_IN_USD ELSE 0 END) AS TOTAL_WITHDRAWAL_AMOUNT
    FROM DW_WAREHOUSE.PUBLIC.GGCORE_PLAYER_PAYMENT_TRANSACTION AS PT
    WHERE PT.CREATED_AT >= '2025-01-01'
      AND PT.STATUS_STRING = 'Completed'
      AND PT.BRAND_ID = 'GGVCOM'
    GROUP BY 1, 2, 3
),

/* 3. Main aggregation of all game stats */
Daily_Gaming_Agg AS (
    SELECT
        a.AGGREGATED_AT,
        a.NETWORK,
        a.BRAND_ID,
        a.SITE_ID,
        a.GGPASS_ID,
        a.GP_ID,
        a.NICKNAME,
        a.COUNTRY_ID,
        SUM(DATEDIFF(min, a.USER_SESSION_STARTED_AT, a.USER_SESSION_FINISHED_AT)) AS TimeOnDeviceMIN,
        COUNT(DISTINCT a.USER_SESSION_ID) AS SessionsPlayed,
        SUM(ROUND(a.BET / a.REQUESTED_EXCHANGE_RATE, 8)) AS BET,
        SUM(ROUND(a.WIN / a.REQUESTED_EXCHANGE_RATE, 8)) AS PaidOutWin,
        SUM(a.BET_COUNT) AS BET_COUNT,
        SUM(a.WON_GAME_COUNT) AS WON_GAME_COUNT,
        SUM(ROUND(a.GGR / a.REQUESTED_EXCHANGE_RATE, 8)) AS GGR,
        SUM(ROUND(a.BET * r.holdperc / a.REQUESTED_EXCHANGE_RATE, 8)) AS Theo_Win,
        SUM(ROUND(a.ESTIMATED_GGR / a.REQUESTED_EXCHANGE_RATE, 8)) AS ESTIMATED_GGR
    FROM DW_WAREHOUSE.PUBLIC.GP_STATISTICS_GAME_CASINO_PER_SESSION AS a
    LEFT JOIN RTP_Data AS r
        ON a.aggregated_at = r.GamingDate
        AND a.brand_id = r.brand_id
        AND a.site_id = r.site_id
        AND a.Game_Type = r.Game_Code
    WHERE a.AGGREGATED_AT >= '2025-01-01'
      AND a.brand_id = 'GGVCOM'
    GROUP BY
        a.AGGREGATED_AT,
        a.NETWORK,
        a.BRAND_ID,
        a.SITE_ID,
        a.GGPASS_ID,
        a.GP_ID,
        a.NICKNAME,
        a.COUNTRY_ID
),

/* 4. Get all daily registrations */
Daily_Registrations AS (
    SELECT
        CAST(CREATEDAT AS DATE) AS Registration_Date,
        GPID AS GP_ID,
        BRANDID AS BRAND_ID
    FROM DW_WAREHOUSE.PUBLIC.GGCORE_PLAYER
    WHERE CREATEDAT >= '2025-01-01'
      AND BRANDID = 'GGVCOM'
      AND GPID IS NOT NULL 
    GROUP BY 1, 2, 3
),

/* 5a. INTERMEDIATE STEP: Combine Gaming + Registration */
Game_And_Reg AS (
    SELECT
        COALESCE(dga.AGGREGATED_AT, dr.Registration_Date) AS AGGREGATED_AT,
        COALESCE(dga.GP_ID, dr.GP_ID) AS GP_ID,
        COALESCE(dga.BRAND_ID, dr.BRAND_ID) AS BRAND_ID,

        dga.NETWORK,
        dga.SITE_ID,
        dga.GGPASS_ID,
        dga.NICKNAME,
        dga.COUNTRY_ID,
        dga.TimeOnDeviceMIN,
        dga.SessionsPlayed,
        dga.BET,
        dga.PaidOutWin,
        dga.BET_COUNT,
        dga.WON_GAME_COUNT,
        dga.GGR,
        dga.Theo_Win,
        dga.ESTIMATED_GGR,
        dr.Registration_Date
    FROM Daily_Gaming_Agg AS dga
    FULL OUTER JOIN Daily_Registrations AS dr
        ON dga.AGGREGATED_AT = dr.Registration_Date
        AND dga.GP_ID = dr.GP_ID
        AND dga.BRAND_ID = dr.BRAND_ID
),

/* 5b. Combine Result + Transactions */
Combined_Player_Activity AS (
    SELECT
        COALESCE(gr.AGGREGATED_AT, pt.TransactionDate) AS AGGREGATED_AT,
        COALESCE(gr.GP_ID, pt.GP_ID) AS GP_ID,
        COALESCE(gr.BRAND_ID, pt.BRAND_ID) AS BRAND_ID,

        -- All columns from the Game_And_Reg CTE
        gr.NETWORK,
        gr.SITE_ID,
        gr.GGPASS_ID,
        gr.NICKNAME,
        gr.COUNTRY_ID,
        gr.TimeOnDeviceMIN,
        gr.SessionsPlayed,
        gr.BET,
        gr.PaidOutWin,
        gr.BET_COUNT,
        gr.WON_GAME_COUNT,
        gr.GGR,
        gr.Theo_Win,
        gr.ESTIMATED_GGR,
        gr.Registration_Date,

        -- All columns from the Daily_Transaction_Stats CTE
        pt.FIRST_DEPOSIT_AMOUNT,
        PT.FIRST_DEPOSIT_COUNT,
        PT.TOTAL_DEPOSIT_COUNT,
        pt.TOTAL_DEPOSIT_AMOUNT,
        pt.TOTAL_WITHDRAWAL_AMOUNT

    FROM Game_And_Reg AS gr
    FULL OUTER JOIN Daily_Transaction_Stats AS pt
        ON gr.AGGREGATED_AT = pt.TransactionDate
        AND gr.GP_ID = pt.GP_ID
        AND gr.BRAND_ID = pt.BRAND_ID
),

/* 6. Identify Bots */
IS_BOT AS (
    SELECT
        DISTINCT 
        GP_ID
    FROM DW_ORIGIN_GLOBAL.GLOBAL_GGVEGAS_DB_GGVEGAS.TNMT_PLAYER 
    WHERE IS_BOT = TRUE
)

/* 7. Final Select: Join all data sources */
SELECT
    cpa.AGGREGATED_AT,

    -- Player/Brand details
    COALESCE(cpa.NETWORK, p.NETWORK) AS NETWORK,
    cpa.BRAND_ID,
    cpa.GP_ID,
    COALESCE(cpa.NICKNAME, p.NICKNAME) AS NICKNAME,

    -- Player Details from Player Table
    p.ID AS PLAYER_ID,
    p.MARKETING_TYPE,
    p.AFFILIATECLICKID,
    p.AFFILIATESITEID,
    p.AFFILIATEMEMBERID,
    p.REGISTRATIONTYPE,
    p.KYCSTATUS,
    DATE_TRUNC('day', p.CREATEDAT) AS REGISTRATION_DATE,

    -- NEW REGISTRATION COLUMN
    CASE WHEN cpa.Registration_Date IS NOT NULL THEN 1 ELSE 0 END AS REGISTRATIONS,

    -- Aggregated Game Stats
    COALESCE(cpa.TimeOnDeviceMIN, 0) AS TimeOnDeviceMIN,
    COALESCE(cpa.SessionsPlayed, 0) AS SessionsPlayed,
    COALESCE(cpa.BET, 0) AS BET,
    COALESCE(cpa.PaidOutWin, 0) AS PaidOutWin,
    COALESCE(cpa.BET_COUNT, 0) AS BET_COUNT,
    COALESCE(cpa.WON_GAME_COUNT, 0) AS WON_GAME_COUNT,
    COALESCE(cpa.GGR, 0) AS GGR,
    COALESCE(cpa.Theo_Win, 0) AS Theo_Win,
    COALESCE(cpa.ESTIMATED_GGR, 0) AS ESTIMATED_GGR,

    -- Aggregated Transaction Stats
    COALESCE(cpa.FIRST_DEPOSIT_AMOUNT, 0) AS FIRST_DEPOSIT_AMOUNT,
    COALESCE(cpa.FIRST_DEPOSIT_COUNT, 0) AS FIRST_DEPOSIT_COUNT,
    COALESCE(cpa.TOTAL_DEPOSIT_COUNT, 0) AS TOTAL_DEPOSIT_COUNT,
    COALESCE(cpa.TOTAL_DEPOSIT_AMOUNT, 0) AS TOTAL_DEPOSIT_AMOUNT,
    COALESCE(cpa.TOTAL_WITHDRAWAL_AMOUNT, 0) AS TOTAL_WITHDRAWAL_AMOUNT

FROM Combined_Player_Activity AS cpa

-- Join for Player info
LEFT JOIN DW_WAREHOUSE.PUBLIC.GGCORE_PLAYER AS p
    ON cpa.GP_ID = p.GPID
    AND cpa.BRAND_ID = p.BRANDID

-- Join against the bot list
LEFT JOIN IS_BOT AS bot
    ON cpa.GP_ID = bot.GP_ID

-- Keep only rows where a bot GP_ID was NOT found
WHERE bot.GP_ID IS NULL;