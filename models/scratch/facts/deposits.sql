{{ config(materialized = 'view') }}

-- Per-(account, token) balances for the tokens listed in `tokens`.
-- Derived from ERC-20 transfers; balances are scaled to token units via decimals.

with token_meta as (
    select address, decimals from {{ ref('tokens') }}
)

, transfers as (
    select
        lower(cast(contract_address as varchar)) as token,
        lower(cast("from" as varchar)) as from_address,
        lower(cast(to as varchar)) as to_address,
        cast(value as decimal(38, 0)) as raw_amount
    from {{ source('erc20_ethereum', 'evt_Transfer') }}
    where lower(cast(contract_address as varchar)) in (
        select address from token_meta
    )
)

, deltas as (
    select to_address as account, token, raw_amount as delta from transfers
    union all
    select from_address as account, token, -raw_amount as delta from transfers
)

, balances as (
    select
        account,
        token,
        sum(delta) as raw_balance
    from deltas
    where account != lower('0x0000000000000000000000000000000000000000')
    group by account, token
)

select
    b.account,
    b.token,
    b.raw_balance / power(cast(10 as decimal(38, 0)), m.decimals) as amount
from balances b
inner join token_meta m on m.address = b.token
where b.raw_balance > 0
