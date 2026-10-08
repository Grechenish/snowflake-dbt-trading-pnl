-- BLOCK. When a fifth of the newest market-data day has no close, the feed is broken (e.g. the
-- close variable was renamed) and PnL would be valued on stale carried-forward prices.
-- It reads int_stock_prices_daily, so dbt build runs it right after that model and, when it fails,
-- skips dim_date, the PnL chain and every report. The incremental table itself is already merged
-- by then; the next good run overwrites the bad days, which are inside the lookback window.
-- The same share is published per day in monitoring_market_data_daily, with a warning above 1%.
with latest_day as (
    select max(trade_date) as trade_date from {{ ref('int_stock_prices_daily') }}
)

select
    prices.trade_date,
    count(*)                             as tickers_received,
    count_if(prices.close_price is null) as tickers_missing_close
from {{ ref('int_stock_prices_daily') }} as prices
inner join latest_day
    on prices.trade_date = latest_day.trade_date
group by prices.trade_date
having div0(count_if(prices.close_price is null), count(*)) > 0.2
