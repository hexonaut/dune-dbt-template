{{ config(materialized = 'view') }}

-- Tokens of interest: Sky USDS plus Spark Savings vaults.
-- Seeded from `tokens_seed`; `underlying` is NULL for base tokens, otherwise
-- the ERC4626 asset() address. `totalSupply` is derived from ERC-20 transfers
-- (mints from 0x0 minus burns to 0x0), scaled by each token's decimals.

with token_meta as (
    select address, name, underlying, decimals from {{ ref('tokens_seed') }}
)

, transfers as (
    select
        lower(cast(contract_address as varchar)) as address,
        lower(cast("from" as varchar)) as from_address,
        lower(cast(to as varchar)) as to_address,
        cast(value as decimal(38, 0)) as raw_amount
    from {{ source('erc20_ethereum', 'evt_Transfer') }}
    where lower(cast(contract_address as varchar)) in (
        select address from token_meta
    )
)

, supply as (
    select
        address,
        sum(case when from_address = lower('0x0000000000000000000000000000000000000000') then raw_amount else 0 end)
          - sum(case when to_address = lower('0x0000000000000000000000000000000000000000') then raw_amount else 0 end) as raw_supply
    from transfers
    group by address
)

select
    m.address,
    m.name,
    m.underlying,
    m.decimals,
    coalesce(s.raw_supply, 0) / power(cast(10 as decimal(38, 0)), m.decimals) as "totalSupply"
from token_meta m
left join supply s on s.address = m.address
