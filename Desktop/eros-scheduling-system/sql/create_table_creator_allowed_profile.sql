-- ============================================================================
-- Table: creator_allowed_profile
-- Purpose: Store per-creator allowed categories and price tiers for PPV/BUMP content
-- Dataset: of-scheduler-proj.eros_scheduling_brain
-- ============================================================================
-- This table defines what content types are ALLOWED for each creator profile.
-- NULL or empty arrays mean "allow all" (no restrictions from allowed list).
-- This is applied BEFORE hard restrictions from creator_caption_restrictions.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile` (
  -- Primary identification
  page_name STRING NOT NULL OPTIONS(description="Creator OnlyFans page name (lowercase)"),

  -- PPV allowed filters
  ppv_allowed_categories ARRAY<STRING> OPTIONS(description="Allowed PPV content categories (NULL/empty = allow all). Examples: ['solo', 'b/g', 'fantasy']"),
  ppv_allowed_price_tiers ARRAY<STRING> OPTIONS(description="Allowed PPV price tiers (NULL/empty = allow all). Examples: ['tier_1', 'tier_2', 'tier_3']"),

  -- BUMP allowed filters
  bump_allowed_categories ARRAY<STRING> OPTIONS(description="Allowed BUMP content categories (NULL/empty = allow all). Examples: ['solo', 'tease']"),
  bump_allowed_price_tiers ARRAY<STRING> OPTIONS(description="Allowed BUMP price tiers (NULL/empty = allow all). Examples: ['tier_1', 'tier_2']"),

  -- Status and metadata
  is_active BOOL NOT NULL OPTIONS(description="Whether this profile is currently active"),
  feature_enabled BOOL NOT NULL OPTIONS(description="Whether caption_restrictions_enabled flag is true for this creator"),

  -- Audit fields
  created_at TIMESTAMP NOT NULL OPTIONS(description="When this profile was created"),
  updated_at TIMESTAMP NOT NULL OPTIONS(description="When this profile was last updated"),
  updated_by STRING OPTIONS(description="User or system that last updated this profile"),
  notes STRING OPTIONS(description="Admin notes about this profile configuration")
)
PARTITION BY DATE(updated_at)
CLUSTER BY page_name, is_active
OPTIONS(
  description="Creator allowed content profiles - defines permitted categories and price tiers per creator. NULL/empty arrays = allow all. Applied before hard restrictions.",
  labels=[("purpose", "allowed_filters"), ("scope", "per_creator")]
);

-- ============================================================================
-- Usage Notes:
-- ============================================================================
-- 1. NULL or empty arrays mean "no restrictions from allowed list" (allow all)
-- 2. Non-empty arrays restrict content to only those values
-- 3. Case-insensitive matching: store lowercase, compare with LOWER()
-- 4. This table is partitioned by DATE(updated_at) for efficient time-based queries
-- 5. Clustered by page_name and is_active for optimal filtering performance
-- 6. Multiple rows per page_name allowed for history tracking
-- 7. Use creator_allowed_profile_v view to get latest active profile per creator
--
-- Example allowed profile (restrictive):
--   page_name: 'ashley_tervort'
--   ppv_allowed_categories: ['solo', 'tease']
--   ppv_allowed_price_tiers: ['tier_1', 'tier_2']
--   bump_allowed_categories: ['solo']
--   bump_allowed_price_tiers: ['tier_1']
--
-- Example allowed profile (permissive):
--   page_name: 'kendra_sunderland'
--   ppv_allowed_categories: NULL  -- allows all categories
--   ppv_allowed_price_tiers: NULL  -- allows all price tiers
--   bump_allowed_categories: NULL
--   bump_allowed_price_tiers: NULL
-- ============================================================================
