{{ config(materialized='view') }}

-- OBSERVE. Completeness of the market data per trading day: how many tickers arrived, and how
-- many of them have no close price (so they are skipped by everything downstream). Nobody is
-- paged by this view; people read it to see trends, and a test on the newest day turns a bad day
-- into a warning (see _marts.yml). The blocking check for a broken feed reads
-- int_stock_prices_daily directly (tests/assert_latest_market_day_has_closes.sql).
with daily as (
    select
        trade_date,
        count(*)                                             as tickers_received,
        count_if(close_price is null)                        as tickers_missing_close,
        count_if(close_price is null and volume is not null) as tickers_volume_only
    from {{ ref('int_stock_prices_daily') }}
    group by trade_date
)

select
    trade_date,
    tickers_received,
    tickers_missing_close,
    tickers_volume_only,
    div0(tickers_missing_close, tickers_received)      as share_missing_close,
    tickers_received
    - lag(tickers_received) over (order by trade_date) as tickers_received_change,
    trade_date = max(trade_date) over ()               as is_latest_day
from daily
