-- BLOCK. Every position must carry all of its trades' cash, on every trading day since its first
-- trade, before anything is published. The trade side is summed straight from int_trades_current
-- and the calendar is counted straight from dim_date, independently of how int_daily_position and
-- int_trading_pnl build them. A difference means a trade was dropped or double counted, or a
-- position is missing a day (e.g. a lost calendar day or a duplicated join).
-- This test reads only models upstream of fct_trading_pnl, so dbt build runs it before
-- fct_trading_pnl and, when it fails, skips fct_trading_pnl and every report built on it. The
-- Treasury and Finance reconciliations repeat the check on the published reports, after the fact.
-- Trades newer than the market data aren't valued yet (assert_trades_within_market_data), so they
-- are left out of both sides.
with last_market_day as (
    select max(date_day) as last_day from {{ ref('dim_date') }}
),

trading_days as (
    select date_day from {{ ref('dim_date') }}
    where is_trading_day
),

trades as (
    select
        book,
        trader,
        instrument,
        currency,
        min(trade_date) as first_trade_date,
        sum(cash_flow)  as cash_from_trades
    from {{ ref('int_trades_current') }}
    where trade_date <= (select last_market_day.last_day from last_market_day)
    group by all
),

expected as (
    select
        trades.book,
        trades.trader,
        trades.instrument,
        trades.currency,
        trades.cash_from_trades,
        count(trading_days.date_day) as expected_days
    from trades
    left join trading_days
        on trades.first_trade_date <= trading_days.date_day
    group by all
),

actual as (
    select
        book,
        trader,
        instrument,
        currency,
        count(*)                               as position_days,
        max_by(cumulative_cash, position_date) as cumulative_cash,
        max(position_date)                     as last_position_date
    from {{ ref('int_trading_pnl') }}
    group by all
)

select
    coalesce(expected.book, actual.book)             as book,
    coalesce(expected.trader, actual.trader)         as trader,
    coalesce(expected.instrument, actual.instrument) as instrument,
    coalesce(expected.currency, actual.currency)     as currency,
    expected.cash_from_trades,
    actual.cumulative_cash,
    expected.expected_days,
    actual.position_days,
    actual.last_position_date
from expected
full outer join actual
    on expected.book = actual.book
        and expected.trader = actual.trader
        and expected.instrument = actual.instrument
        and expected.currency = actual.currency
where expected.book is null
    or actual.book is null
    or expected.expected_days <> actual.position_days
    or actual.last_position_date <> (select last_market_day.last_day from last_market_day)
    or abs(coalesce(expected.cash_from_trades, 0) - coalesce(actual.cumulative_cash, 0)) > 0.01
