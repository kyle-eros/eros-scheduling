"""
Contextual Caption Selector with Energy Matching
Selects captions based on time-of-day energy, content availability, and performance
"""

import pandas as pd
import numpy as np
from google.cloud import bigquery
from typing import Dict, List, Optional, Tuple
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ContextualCaptionSelector:
    """
    Intelligent caption selection with:
    - Time-of-day energy matching (morning/afternoon/evening/night)
    - vault_matrix content validation (CRITICAL)
    - Performance-based scoring
    - Diversity enforcement
    """

    def __init__(self, project_id: str = "of-scheduler-proj"):
        self.project_id = project_id
        self.dataset_id = "eros_scheduling_brain"
        self.client = bigquery.Client(project=project_id)

        # Energy profiles by time of day
        self.energy_profiles = {
            'morning': {  # 5-11
                'energy_level': 'rising',
                'tone': ['playful', 'teasing', 'fresh', 'wake_up'],
                'keywords': ['morning', 'wake', 'good morning', 'start your day', 'coffee'],
                'content_preference': ['solo', 'tease', 'shower', 'bed']
            },
            'afternoon': {  # 12-16
                'energy_level': 'peak',
                'tone': ['direct', 'confident', 'explicit', 'bold'],
                'keywords': ['right now', 'today', 'available', 'ready', 'waiting'],
                'content_preference': ['boy_girl', 'solo', 'bundle', 'premium']
            },
            'evening': {  # 17-21
                'energy_level': 'prime_time',
                'tone': ['seductive', 'intimate', 'exclusive', 'special'],
                'keywords': ['tonight', 'evening', 'exclusive', 'just for you', 'special'],
                'content_preference': ['boy_girl', 'girl_girl', 'premium', 'exclusive']
            },
            'late_night': {  # 22-4
                'energy_level': 'intimate',
                'tone': ['naughty', 'dirty', 'wild', 'cant_sleep'],
                'keywords': ['late night', 'cant sleep', 'up late', 'naughty', 'wild'],
                'content_preference': ['fetish', 'extreme', 'dirty', 'raw']
            }
        }

    def select_captions_for_schedule(
        self,
        page_name: str,
        time_slots: List[Tuple[int, str, str]],  # (hour, message_type, price_tier)
        available_content: List[str],
        recently_used_caption_ids: List[int] = None
    ) -> List[Dict]:
        """
        Select optimal captions for a schedule.
        Returns list of caption assignments with explanations.
        """

        if recently_used_caption_ids is None:
            recently_used_caption_ids = []

        # Fetch available captions
        captions = self._fetch_available_captions(
            page_name,
            available_content,
            recently_used_caption_ids
        )

        if captions.empty:
            logger.warning(f"No captions available for {page_name}")
            return []

        # Select captions for each slot
        selected = []
        used_ids = set()

        for hour, message_type, price_tier in time_slots:
            # Get time period
            time_period = self._get_time_period(hour)

            # Select best caption for this slot
            caption = self._select_best_caption(
                captions,
                hour,
                message_type,
                price_tier,
                time_period,
                used_ids
            )

            if caption is not None:
                selected.append({
                    'hour': hour,
                    'caption_id': caption['caption_id'],
                    'caption_text': caption['caption_text'],
                    'content_category': caption['content_category'],
                    'price_tier': caption['price_tier'],
                    'performance_score': caption['overall_performance_score'],
                    'energy_match_score': caption['energy_match_score'],
                    'selection_reason': caption['selection_reason']
                })
                used_ids.add(caption['caption_id'])

        return selected

    def _fetch_available_captions(
        self,
        page_name: str,
        available_content: List[str],
        exclude_ids: List[int]
    ) -> pd.DataFrame:
        """
        Fetch available captions filtered by vault_matrix.
        CRITICAL: Only return captions creator has content for.
        """

        # Build content filter based on vault_matrix
        content_conditions = []
        for content_type in available_content:
            # Match various naming conventions
            content_conditions.append(
                f"LOWER(cb.content_category) LIKE '%{content_type.lower()}%'"
            )

        content_filter = " OR ".join(content_conditions) if content_conditions else "1=1"

        # Build exclusion filter
        exclude_filter = ""
        if exclude_ids:
            exclude_filter = f"AND cb.caption_id NOT IN ({','.join(map(str, exclude_ids))})"

        query = f"""
        WITH recent_usage AS (
            SELECT
                caption_id,
                MAX(scheduled_send_date) as last_used,
                COUNT(*) as times_used
            FROM `{self.project_id}.{self.dataset_id}.active_caption_assignments`
            WHERE page_name = '{page_name}'
                AND scheduled_send_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
            GROUP BY caption_id
        )
        SELECT
            cb.caption_id,
            cb.caption_text,
            cb.content_category,
            cb.price_tier,
            cb.validation_level,
            cb.total_sends,
            cb.lifetime_revenue,
            cb.avg_conversion_rate,
            cb.overall_performance_score,
            cb.days_since_last_use,
            COALESCE(ru.times_used, 0) as recent_uses,
            COALESCE(DATE_DIFF(CURRENT_DATE(), ru.last_used, DAY), 999) as days_since_used_by_creator
        FROM `{self.project_id}.{self.dataset_id}.caption_bank` cb
        LEFT JOIN recent_usage ru ON cb.caption_id = ru.caption_id
        WHERE cb.usage_status = 'available'
            AND cb.validation_level IN ('medium', 'high')
            AND ({content_filter})
            AND cb.days_since_last_use > 30  -- Global freshness
            {exclude_filter}
        ORDER BY
            cb.overall_performance_score DESC,
            cb.lifetime_revenue DESC
        LIMIT 1000
        """

        try:
            return self.client.query(query).to_dataframe()
        except Exception as e:
            logger.error(f"Failed to fetch captions: {e}")
            return pd.DataFrame()

    def _get_time_period(self, hour: int) -> str:
        """Map hour to time period"""
        if 5 <= hour < 12:
            return 'morning'
        elif 12 <= hour < 17:
            return 'afternoon'
        elif 17 <= hour < 22:
            return 'evening'
        else:
            return 'late_night'

    def _select_best_caption(
        self,
        captions: pd.DataFrame,
        hour: int,
        message_type: str,
        price_tier: str,
        time_period: str,
        used_ids: set
    ) -> Optional[Dict]:
        """Select best caption for a specific slot"""

        # Filter out already used
        available = captions[~captions['caption_id'].isin(used_ids)].copy()

        if available.empty:
            return None

        # Filter by price tier (if not free)
        if price_tier != 'free':
            tier_match = available[available['price_tier'] == price_tier]
            if not tier_match.empty:
                available = tier_match

        # Filter by content category if specific
        if message_type != 'general_ppv':
            content_match = available[
                available['content_category'].str.lower().str.contains(
                    message_type.replace('_', '|'),
                    na=False,
                    regex=True
                )
            ]
            if not content_match.empty:
                available = content_match

        if available.empty:
            # Fallback to any available caption
            available = captions[~captions['caption_id'].isin(used_ids)]

        if available.empty:
            return None

        # Calculate energy match score
        available['energy_match_score'] = available['caption_text'].apply(
            lambda text: self._calculate_energy_match(text, time_period)
        )

        # Calculate final score
        available['final_score'] = (
            (available['overall_performance_score'] / 100) * 0.4 +
            (available['avg_conversion_rate'] / 100) * 0.3 +
            (available['lifetime_revenue'] / available['lifetime_revenue'].max()) * 0.2 +
            available['energy_match_score'] * 0.1
        )

        # Add randomness for diversity (±20%)
        available['final_score'] *= (0.8 + np.random.random(len(available)) * 0.4)

        # Prefer captions not used recently by this creator
        available.loc[available['days_since_used_by_creator'] > 45, 'final_score'] *= 1.2

        # Select best
        best = available.nlargest(1, 'final_score').iloc[0]

        return {
            'caption_id': int(best['caption_id']),
            'caption_text': best['caption_text'],
            'content_category': best['content_category'],
            'price_tier': best['price_tier'],
            'overall_performance_score': float(best['overall_performance_score']),
            'energy_match_score': float(best['energy_match_score']),
            'selection_reason': self._generate_selection_reason(
                best,
                time_period,
                message_type
            )
        }

    def _calculate_energy_match(self, caption_text: str, time_period: str) -> float:
        """Calculate how well caption matches time period energy"""

        if not isinstance(caption_text, str):
            return 0.5

        text_lower = caption_text.lower()
        profile = self.energy_profiles.get(time_period, {})

        score = 0.5  # Base score

        # Check for matching keywords
        keywords = profile.get('keywords', [])
        keyword_matches = sum(1 for kw in keywords if kw in text_lower)
        score += (keyword_matches / max(len(keywords), 1)) * 0.3

        # Check tone indicators
        tone_indicators = profile.get('tone', [])
        tone_matches = sum(1 for tone in tone_indicators if tone in text_lower)
        score += (tone_matches / max(len(tone_indicators), 1)) * 0.2

        return min(score, 1.0)

    def _generate_selection_reason(
        self,
        caption: pd.Series,
        time_period: str,
        message_type: str
    ) -> str:
        """Generate human-readable reason for caption selection"""

        reasons = []

        # Performance
        if caption['overall_performance_score'] > 80:
            reasons.append("High performance score")
        elif caption['overall_performance_score'] > 60:
            reasons.append("Good performance score")

        # Energy match
        if caption['energy_match_score'] > 0.7:
            reasons.append(f"Excellent {time_period} energy match")
        elif caption['energy_match_score'] > 0.5:
            reasons.append(f"Good {time_period} match")

        # Freshness
        if caption.get('days_since_used_by_creator', 999) > 60:
            reasons.append("Fresh for this creator")

        # Type match
        if message_type.replace('_', ' ') in str(caption['content_category']).lower():
            reasons.append(f"Perfect {message_type} match")

        return " | ".join(reasons) if reasons else "Standard selection"


class CaptionDiversityEnforcer:
    """Ensures caption diversity and prevents repetitive patterns"""

    @staticmethod
    def check_diversity(selected_captions: List[Dict]) -> Dict:
        """Check if selected captions have good diversity"""

        if not selected_captions:
            return {'is_diverse': True, 'issues': []}

        issues = []

        # Check content category diversity
        categories = [c['content_category'] for c in selected_captions]
        category_counts = pd.Series(categories).value_counts()

        max_single_category = category_counts.max()
        if max_single_category > len(selected_captions) * 0.4:
            issues.append(f"Too many {category_counts.idxmax()} captions ({max_single_category})")

        # Check for duplicate captions
        caption_ids = [c['caption_id'] for c in selected_captions]
        if len(caption_ids) != len(set(caption_ids)):
            issues.append("Duplicate captions detected")

        # Check price tier distribution
        price_tiers = [c.get('price_tier', 'mid') for c in selected_captions]
        tier_counts = pd.Series(price_tiers).value_counts()

        # Should have mix of tiers
        if len(tier_counts) < 2:
            issues.append("All captions same price tier")

        return {
            'is_diverse': len(issues) == 0,
            'issues': issues,
            'diversity_score': 1.0 - (len(issues) * 0.2)
        }


if __name__ == "__main__":
    # Test
    selector = ContextualCaptionSelector()

    # Example time slots: (hour, message_type, price_tier)
    slots = [
        (9, 'solo', 'mid'),
        (14, 'boy_girl', 'premium'),
        (18, 'tease', 'free'),
        (21, 'solo', 'mid')
    ]

    available_content = ['Solo', 'BJ', 'BG', 'Tease']

    result = selector.select_captions_for_schedule(
        page_name="mayahill",
        time_slots=slots,
        available_content=available_content
    )

    print(f"Selected {len(result)} captions")
    for cap in result:
        print(f"Hour {cap['hour']}: {cap['selection_reason']}")
