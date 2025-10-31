#!/usr/bin/env python3
"""
EROS Schedule Builder - Production Ready
=========================================
Generates weekly schedules with account-size-based volume controls,
RED/YELLOW/GREEN saturation response, and BigQuery persistence.

Project: of-scheduler-proj
Dataset: eros_scheduling_brain
Timezone: America/Los_Angeles

Features:
- Account size classification (MICRO, SMALL, MEDIUM, LARGE, MEGA)
- Saturation-based volume adjustments (RED/YELLOW/GREEN zones)
- BigQuery-backed caption selection via stored procedures
- Atomic caption locking with conflict prevention
- CSV export with comprehensive metadata
- Full audit logging and error handling
"""

from zoneinfo import ZoneInfo
from google.cloud import bigquery
from google.api_core import retry
import pandas as pd
import json
import logging
import sys
from datetime import datetime, timedelta, time, date
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass, asdict
import random

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# LA Timezone
LA_TZ = ZoneInfo("America/Los_Angeles")

# ============================================================================
# DATA STRUCTURES
# ============================================================================

@dataclass
class AccountSizeParameters:
    """Volume and timing parameters by account size tier"""
    size_tier: str
    weekly_ppv_min: int
    weekly_ppv_max: int
    weekly_bump_min: int
    weekly_bump_max: int
    min_gap_hours: float
    max_messages_per_day: int


@dataclass
class SaturationResponse:
    """Actions based on saturation zone"""
    zone: str  # GREEN, YELLOW, RED
    volume_multiplier: float
    bump_increase_ratio: float
    gap_extension_hours: float
    cooling_days_required: int
    actions: List[str]


# ============================================================================
# ACCOUNT SIZE CONFIGURATIONS
# ============================================================================

ACCOUNT_SIZE_CONFIGS = {
    'MICRO': AccountSizeParameters(
        size_tier='MICRO',
        weekly_ppv_min=5,
        weekly_ppv_max=7,
        weekly_bump_min=3,
        weekly_bump_max=5,
        min_gap_hours=3.0,
        max_messages_per_day=8
    ),
    'SMALL': AccountSizeParameters(
        size_tier='SMALL',
        weekly_ppv_min=7,
        weekly_ppv_max=10,
        weekly_bump_min=5,
        weekly_bump_max=7,
        min_gap_hours=2.5,
        max_messages_per_day=10
    ),
    'MEDIUM': AccountSizeParameters(
        size_tier='MEDIUM',
        weekly_ppv_min=10,
        weekly_ppv_max=14,
        weekly_bump_min=7,
        weekly_bump_max=10,
        min_gap_hours=2.0,
        max_messages_per_day=15
    ),
    'LARGE': AccountSizeParameters(
        size_tier='LARGE',
        weekly_ppv_min=14,
        weekly_ppv_max=18,
        weekly_bump_min=10,
        weekly_bump_max=14,
        min_gap_hours=1.5,
        max_messages_per_day=20
    ),
    'MEGA': AccountSizeParameters(
        size_tier='MEGA',
        weekly_ppv_min=18,
        weekly_ppv_max=25,
        weekly_bump_min=14,
        weekly_bump_max=18,
        min_gap_hours=1.25,
        max_messages_per_day=25
    )
}

# ============================================================================
# SATURATION RESPONSE CONFIGURATIONS
# ============================================================================

SATURATION_RESPONSES = {
    'GREEN': SaturationResponse(
        zone='GREEN',
        volume_multiplier=1.0,
        bump_increase_ratio=1.0,
        gap_extension_hours=0.0,
        cooling_days_required=0,
        actions=['Continue normal operations', 'Consider gradual volume increase']
    ),
    'YELLOW': SaturationResponse(
        zone='YELLOW',
        volume_multiplier=0.75,  # 25% reduction
        bump_increase_ratio=1.20,  # 20% more bumps
        gap_extension_hours=0.5,  # Add 30 min to gaps
        cooling_days_required=0,
        actions=[
            'Reduce PPV volume by 25%',
            'Increase free engagement content by 20%',
            'Extend gaps between PPVs'
        ]
    ),
    'RED': SaturationResponse(
        zone='RED',
        volume_multiplier=0.5,  # 50% reduction
        bump_increase_ratio=2.0,  # Double the bumps
        gap_extension_hours=1.0,  # Add 1 hour to gaps
        cooling_days_required=2,  # 2 days with NO PPVs
        actions=[
            'MANDATORY: Insert 2 cooling days with ZERO PPVs',
            'After cooling: Resume at 50% volume',
            'Send only free bumps during cooling',
            'Progressive ramp: +10% volume per day until YELLOW'
        ]
    )
}

# ============================================================================
# MESSAGE TYPE NORMALIZATION
# ============================================================================

MESSAGE_TYPE_MAPPING = {
    'Unlock': 'PPV',
    'Photo bump': 'Bump',
    'Free content': 'Bump',
    'PPV': 'PPV',
    'Bump': 'Bump'
}

PRICE_TIER_MAPPING = {
    'budget': 'Budget',
    'mid': 'Mid',
    'premium': 'Premium',
    'luxury': 'Luxury',
    'standard': 'Mid'
}

# ============================================================================
# SCHEDULE BUILDER CLASS
# ============================================================================

class ScheduleBuilder:
    """
    Production-ready schedule builder with BigQuery integration.

    Responsibilities:
    - Query creator performance analysis
    - Calculate volume targets based on account size and saturation
    - Select captions via stored procedure
    - Build time-optimized weekly schedule
    - Persist schedule to BigQuery
    - Lock caption assignments atomically
    - Export schedule to CSV
    """

    def __init__(self, project_id: str, dataset: str):
        """
        Initialize schedule builder with BigQuery client.

        Args:
            project_id: GCP project ID (e.g., 'of-scheduler-proj')
            dataset: BigQuery dataset name (e.g., 'eros_scheduling_brain')
        """
        self.project_id = project_id
        self.dataset = dataset
        self.client = bigquery.Client(project=project_id)
        logger.info(f"Initialized ScheduleBuilder for {project_id}.{dataset}")

    def analyze_creator(self, page_name: str) -> Dict[str, Any]:
        """
        Call analyze_creator_performance procedure to get comprehensive creator metrics.

        Args:
            page_name: Creator's page name (e.g., 'jadebri')

        Returns:
            Dict containing:
                - account_classification: size tier, volume targets
                - behavioral_segment: segment label, RPR metrics
                - saturation: score, risk level, recommended actions
                - performance metrics by trigger, category, day, time
        """
        logger.info(f"Analyzing creator performance for {page_name}")

        query = f"""
        DECLARE performance_report STRING;

        CALL `{self.project_id}.{self.dataset}.analyze_creator_performance`(
            @page_name,
            performance_report
        );

        SELECT performance_report;
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("page_name", "STRING", page_name)
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            for row in results:
                report_json = row.performance_report
                report = json.loads(report_json)
                logger.info(f"Creator analysis complete: {report.get('account_classification', {}).get('size_tier', 'UNKNOWN')} tier")
                return report

        except Exception as e:
            logger.error(f"Failed to analyze creator {page_name}: {e}")
            raise

    def calculate_volume_targets(
        self,
        account_size: str,
        saturation_score: float,
        saturation_tolerance: float = 0.5
    ) -> Tuple[int, int, str]:
        """
        Calculate PPV and Bump volume targets based on account size and saturation.

        Args:
            account_size: Size tier (MICRO, SMALL, MEDIUM, LARGE, MEGA)
            saturation_score: Saturation score from 0.0 to 1.0
            saturation_tolerance: Threshold for saturation sensitivity

        Returns:
            Tuple of (ppv_count, bump_count, saturation_zone)
        """
        # Default to MEDIUM if unknown size
        size_params = ACCOUNT_SIZE_CONFIGS.get(account_size, ACCOUNT_SIZE_CONFIGS['MEDIUM'])

        # Determine saturation zone
        if saturation_score < saturation_tolerance * 0.6:
            zone = 'GREEN'
        elif saturation_score < saturation_tolerance:
            zone = 'YELLOW'
        else:
            zone = 'RED'

        response = SATURATION_RESPONSES[zone]

        # Calculate base weekly targets (average of min/max)
        base_ppv = (size_params.weekly_ppv_min + size_params.weekly_ppv_max) // 2
        base_bump = (size_params.weekly_bump_min + size_params.weekly_bump_max) // 2

        # Apply saturation adjustments
        adjusted_ppv = int(base_ppv * response.volume_multiplier)
        adjusted_bump = int(base_bump * response.bump_increase_ratio)

        logger.info(
            f"Volume targets: {adjusted_ppv} PPVs, {adjusted_bump} Bumps "
            f"(zone={zone}, base={base_ppv}/{base_bump}, multiplier={response.volume_multiplier:.2f})"
        )

        return adjusted_ppv, adjusted_bump, zone

    def select_captions(
        self,
        page_name: str,
        behavioral_segment: str,
        num_budget: int,
        num_mid: int,
        num_premium: int,
        num_bump: int
    ) -> List[Dict[str, Any]]:
        """
        Call select_captions_for_creator procedure to get optimized caption selection.

        Args:
            page_name: Creator's page name
            behavioral_segment: Segment label (BUDGET, STANDARD, PREMIUM, LUXURY)
            num_budget: Number of budget-tier captions needed
            num_mid: Number of mid-tier captions needed
            num_premium: Number of premium-tier captions needed
            num_bump: Number of bump captions needed

        Returns:
            List of caption dictionaries with metadata
        """
        logger.info(
            f"Selecting captions for {page_name}: "
            f"budget={num_budget}, mid={num_mid}, premium={num_premium}, bump={num_bump}"
        )

        query = f"""
        CALL `{self.project_id}.{self.dataset}.select_captions_for_creator`(
            @page_name,
            @behavioral_segment,
            @num_budget,
            @num_mid,
            @num_premium,
            @num_bump
        );

        SELECT
            caption_id,
            caption_text,
            price_tier,
            content_category,
            has_urgency,
            composite_score,
            thompson_sample,
            diversity_penalty,
            final_score
        FROM caption_selection_results
        ORDER BY final_score DESC;
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("page_name", "STRING", page_name),
                bigquery.ScalarQueryParameter("behavioral_segment", "STRING", behavioral_segment),
                bigquery.ScalarQueryParameter("num_budget", "INT64", num_budget),
                bigquery.ScalarQueryParameter("num_mid", "INT64", num_mid),
                bigquery.ScalarQueryParameter("num_premium", "INT64", num_premium),
                bigquery.ScalarQueryParameter("num_bump", "INT64", num_bump)
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            captions = []
            for row in results:
                captions.append({
                    'caption_id': row.caption_id,
                    'caption_text': row.caption_text,
                    'price_tier': row.price_tier,
                    'content_category': row.content_category,
                    'has_urgency': row.has_urgency,
                    'performance_score': row.composite_score
                })

            logger.info(f"Selected {len(captions)} captions")
            return captions

        except Exception as e:
            logger.error(f"Failed to select captions for {page_name}: {e}")
            raise

    def build_schedule(
        self,
        page_name: str,
        start_date: str,
        override_params: Optional[Dict[str, Any]] = None
    ) -> Tuple[str, pd.DataFrame]:
        """
        Build complete 7-day schedule with BigQuery persistence.

        Args:
            page_name: Creator's page name
            start_date: Start date in YYYY-MM-DD format
            override_params: Optional dict to override volume calculations

        Returns:
            Tuple of (schedule_id, schedule_dataframe)
        """
        logger.info(f"Building schedule for {page_name} starting {start_date}")
        start_time = datetime.now(LA_TZ)

        # Parse start date
        start_dt = datetime.strptime(start_date, '%Y-%m-%d').replace(tzinfo=LA_TZ)

        # Step 1: Analyze creator
        analysis = self.analyze_creator(page_name)

        account_class = analysis.get('account_classification', {})
        segment = analysis.get('behavioral_segment', {})
        saturation = analysis.get('saturation', {})

        account_size = account_class.get('size_tier', 'MEDIUM')
        behavioral_segment = segment.get('segment_label', 'STANDARD')
        saturation_score = saturation.get('saturation_score', 0.3)
        saturation_tolerance = account_class.get('saturation_tolerance', 0.5)

        # Step 2: Calculate volume targets
        if override_params:
            ppv_count = override_params.get('ppv_count', 10)
            bump_count = override_params.get('bump_count', 7)
            zone = override_params.get('zone', 'GREEN')
        else:
            ppv_count, bump_count, zone = self.calculate_volume_targets(
                account_size,
                saturation_score,
                saturation_tolerance
            )

        # Distribute PPV counts across price tiers based on segment
        tier_distribution = self._get_tier_distribution(behavioral_segment, ppv_count)

        # Step 3: Select captions
        captions = self.select_captions(
            page_name,
            behavioral_segment,
            tier_distribution['budget'],
            tier_distribution['mid'],
            tier_distribution['premium'],
            bump_count
        )

        if not captions:
            raise ValueError(f"No captions selected for {page_name}")

        # Step 4: Build time slots
        schedule_messages = self._build_time_slots(
            captions,
            start_dt,
            ppv_count,
            bump_count,
            zone,
            account_size,
            analysis.get('time_window_optimization', [])
        )

        # Step 5: Generate schedule ID
        schedule_id = f"sched_{datetime.now(LA_TZ).strftime('%Y%m%d_%H%M%S')}_{page_name}"

        # Step 6: Persist schedule to BigQuery
        self._persist_schedule(schedule_id, page_name, schedule_messages, analysis, zone)

        # Step 7: Lock caption assignments
        self._lock_caption_assignments(schedule_id, page_name, schedule_messages)

        # Step 8: Build DataFrame for CSV export
        df = self._build_dataframe(schedule_id, page_name, schedule_messages)

        end_time = datetime.now(LA_TZ)
        duration = (end_time - start_time).total_seconds()

        logger.info(
            f"Schedule {schedule_id} built successfully in {duration:.2f}s: "
            f"{len(schedule_messages)} messages, {ppv_count} PPVs, {bump_count} Bumps"
        )

        # Log to export log
        self._log_export(schedule_id, page_name, len(schedule_messages), duration, None)

        return schedule_id, df

    def _get_tier_distribution(self, segment: str, total_ppv: int) -> Dict[str, int]:
        """
        Distribute PPV count across price tiers based on behavioral segment.

        Budget segment: More budget tier
        Premium segment: More premium tier
        Standard: Balanced mix
        """
        if segment == 'BUDGET' or segment == 'EXPLORATORY':
            return {
                'budget': int(total_ppv * 0.60),
                'mid': int(total_ppv * 0.30),
                'premium': int(total_ppv * 0.10)
            }
        elif segment == 'PREMIUM' or segment == 'LUXURY':
            return {
                'budget': int(total_ppv * 0.15),
                'mid': int(total_ppv * 0.35),
                'premium': int(total_ppv * 0.50)
            }
        else:  # STANDARD
            return {
                'budget': int(total_ppv * 0.30),
                'mid': int(total_ppv * 0.45),
                'premium': int(total_ppv * 0.25)
            }

    def _build_time_slots(
        self,
        captions: List[Dict],
        start_dt: datetime,
        ppv_count: int,
        bump_count: int,
        zone: str,
        account_size: str,
        time_windows: List[Dict]
    ) -> List[Dict[str, Any]]:
        """
        Build time-optimized schedule with proper gaps and variety.

        Args:
            captions: Selected captions
            start_dt: Schedule start datetime
            ppv_count: Target PPV count
            bump_count: Target bump count
            zone: Saturation zone (GREEN/YELLOW/RED)
            account_size: Account size tier
            time_windows: Optimal time windows from analysis

        Returns:
            List of scheduled message dicts
        """
        size_params = ACCOUNT_SIZE_CONFIGS.get(account_size, ACCOUNT_SIZE_CONFIGS['MEDIUM'])
        response = SATURATION_RESPONSES[zone]

        # Separate PPV and Bump captions
        ppv_captions = [c for c in captions if c['price_tier'] not in ['Bump', 'Free']]
        bump_captions = [c for c in captions if c['price_tier'] in ['Bump', 'Free']]

        # Extract peak hours from time windows
        peak_hours = self._extract_peak_hours(time_windows)

        messages = []
        cooling_days = response.cooling_days_required

        # Build schedule day by day
        for day_offset in range(7):
            current_date = (start_dt + timedelta(days=day_offset)).date()
            is_cooling_day = day_offset < cooling_days

            if is_cooling_day:
                # Cooling day: Only bumps
                daily_messages = self._build_cooling_day(current_date, bump_captions)
            else:
                # Normal day: PPVs and Bumps
                daily_ppv = ppv_count // (7 - cooling_days)
                daily_bump = bump_count // 7

                daily_messages = self._build_daily_schedule(
                    current_date,
                    ppv_captions,
                    bump_captions,
                    daily_ppv,
                    daily_bump,
                    peak_hours,
                    size_params.min_gap_hours + response.gap_extension_hours
                )

            messages.extend(daily_messages)

        return sorted(messages, key=lambda x: x['scheduled_send_time'])

    def _extract_peak_hours(self, time_windows: List[Dict]) -> Dict[str, List[int]]:
        """Extract peak hours by day type from time window analysis."""
        weekday_hours = []
        weekend_hours = []

        for window in time_windows:
            day_type = window.get('day_type', 'Weekday')
            hour = window.get('hour_24', 12)

            if day_type == 'Weekend':
                weekend_hours.append(hour)
            else:
                weekday_hours.append(hour)

        # Fallback defaults
        if not weekday_hours:
            weekday_hours = [9, 13, 17, 19, 20]
        if not weekend_hours:
            weekend_hours = [11, 14, 18, 21]

        return {
            'Weekday': list(set(weekday_hours))[:8],  # Top 8 hours
            'Weekend': list(set(weekend_hours))[:8]
        }

    def _build_cooling_day(self, current_date: date, bump_captions: List[Dict]) -> List[Dict]:
        """Build cooling day schedule with bumps only (no PPVs)."""
        messages = []

        # Morning bump
        if bump_captions:
            caption = random.choice(bump_captions)
            messages.append({
                'scheduled_send_time': datetime.combine(current_date, time(9, 0), LA_TZ),
                'message_type': 'Bump',
                'caption_id': caption['caption_id'],
                'caption_text': caption['caption_text'],
                'price_tier': 'Free',
                'content_category': caption.get('content_category', 'Engagement'),
                'has_urgency': False,
                'performance_score': 0.0
            })

        # Afternoon bump
        if len(bump_captions) > 1:
            caption = random.choice([c for c in bump_captions if c != messages[0]])
            messages.append({
                'scheduled_send_time': datetime.combine(current_date, time(14, 30), LA_TZ),
                'message_type': 'Bump',
                'caption_id': caption['caption_id'],
                'caption_text': caption['caption_text'],
                'price_tier': 'Free',
                'content_category': caption.get('content_category', 'Engagement'),
                'has_urgency': False,
                'performance_score': 0.0
            })

        # Evening bump
        if len(bump_captions) > 2:
            used = [m['caption_id'] for m in messages]
            remaining = [c for c in bump_captions if c['caption_id'] not in used]
            if remaining:
                caption = random.choice(remaining)
                messages.append({
                    'scheduled_send_time': datetime.combine(current_date, time(20, 0), LA_TZ),
                    'message_type': 'Bump',
                    'caption_id': caption['caption_id'],
                    'caption_text': caption['caption_text'],
                    'price_tier': 'Free',
                    'content_category': caption.get('content_category', 'Engagement'),
                    'has_urgency': False,
                    'performance_score': 0.0
                })

        return messages

    def _build_daily_schedule(
        self,
        current_date: date,
        ppv_captions: List[Dict],
        bump_captions: List[Dict],
        daily_ppv: int,
        daily_bump: int,
        peak_hours: Dict[str, List[int]],
        min_gap_hours: float
    ) -> List[Dict]:
        """Build schedule for a normal (non-cooling) day."""
        messages = []
        day_of_week = current_date.weekday()
        day_type = 'Weekend' if day_of_week in [5, 6] else 'Weekday'
        hours = peak_hours.get(day_type, [10, 13, 17, 20])

        # Schedule PPVs at peak hours
        used_ppv_ids = []
        for i in range(min(daily_ppv, len(ppv_captions))):
            # Select caption with variety
            available = [c for c in ppv_captions if c['caption_id'] not in used_ppv_ids]
            if not available:
                break

            caption = available[i % len(available)]
            used_ppv_ids.append(caption['caption_id'])

            # Calculate send time with jitter
            hour_idx = i % len(hours)
            hour = hours[hour_idx]
            minute = random.randint(0, 59)

            # Apply minimum gap
            send_time = datetime.combine(current_date, time(hour, minute), LA_TZ)
            if messages:
                last_time = messages[-1]['scheduled_send_time']
                min_gap_td = timedelta(hours=min_gap_hours)
                if send_time - last_time < min_gap_td:
                    send_time = last_time + min_gap_td

            # Ensure within day bounds
            if send_time.hour >= 22:
                send_time = datetime.combine(current_date, time(21, 30), LA_TZ)

            messages.append({
                'scheduled_send_time': send_time,
                'message_type': 'PPV',
                'caption_id': caption['caption_id'],
                'caption_text': caption['caption_text'],
                'price_tier': PRICE_TIER_MAPPING.get(caption['price_tier'].lower(), caption['price_tier']),
                'content_category': caption.get('content_category', 'General'),
                'has_urgency': caption.get('has_urgency', False),
                'performance_score': caption.get('performance_score', 0.5)
            })

        # Add bumps between PPVs
        used_bump_ids = []
        for i in range(min(daily_bump, len(bump_captions))):
            available = [c for c in bump_captions if c['caption_id'] not in used_bump_ids]
            if not available:
                break

            caption = available[i % len(available)]
            used_bump_ids.append(caption['caption_id'])

            # Place between PPVs or at morning/evening
            if i == 0:
                # Morning bump
                send_time = datetime.combine(current_date, time(8, 30), LA_TZ)
            elif i == daily_bump - 1:
                # Evening bump
                send_time = datetime.combine(current_date, time(21, 0), LA_TZ)
            else:
                # Between PPVs
                if len(messages) > 1:
                    mid_idx = len(messages) // 2
                    prev_time = messages[mid_idx - 1]['scheduled_send_time']
                    next_time = messages[mid_idx]['scheduled_send_time']
                    gap = (next_time - prev_time).total_seconds() / 2
                    send_time = prev_time + timedelta(seconds=gap)
                else:
                    send_time = datetime.combine(current_date, time(12 + i, 0), LA_TZ)

            messages.append({
                'scheduled_send_time': send_time,
                'message_type': 'Bump',
                'caption_id': caption['caption_id'],
                'caption_text': caption['caption_text'],
                'price_tier': 'Free',
                'content_category': caption.get('content_category', 'Engagement'),
                'has_urgency': False,
                'performance_score': 0.0
            })

        return messages

    def _persist_schedule(
        self,
        schedule_id: str,
        page_name: str,
        messages: List[Dict],
        analysis: Dict,
        zone: str
    ):
        """Persist schedule to schedule_recommendations table."""
        logger.info(f"Persisting schedule {schedule_id} to BigQuery")

        # Build schedule JSON
        schedule_json = json.dumps({
            'schedule_id': schedule_id,
            'page_name': page_name,
            'created_at': datetime.now(LA_TZ).isoformat(),
            'saturation_zone': zone,
            'account_tier': analysis.get('account_classification', {}).get('size_tier', 'MEDIUM'),
            'total_messages': len(messages),
            'total_ppvs': sum(1 for m in messages if m['message_type'] == 'PPV'),
            'total_bumps': sum(1 for m in messages if m['message_type'] == 'Bump'),
            'messages': messages
        }, default=str)

        # Insert into schedule_recommendations table (create if not exists)
        table_ref = f"{self.project_id}.{self.dataset}.schedule_recommendations"

        insert_query = f"""
        INSERT INTO `{table_ref}` (
            schedule_id,
            page_name,
            created_at,
            schedule_json,
            total_messages,
            saturation_zone
        ) VALUES (
            @schedule_id,
            @page_name,
            @created_at,
            @schedule_json,
            @total_messages,
            @saturation_zone
        )
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("schedule_id", "STRING", schedule_id),
                bigquery.ScalarQueryParameter("page_name", "STRING", page_name),
                bigquery.ScalarQueryParameter("created_at", "TIMESTAMP", datetime.now(LA_TZ)),
                bigquery.ScalarQueryParameter("schedule_json", "STRING", schedule_json),
                bigquery.ScalarQueryParameter("total_messages", "INT64", len(messages)),
                bigquery.ScalarQueryParameter("saturation_zone", "STRING", zone)
            ]
        )

        try:
            # Try to insert; if table doesn't exist, create it first
            query_job = self.client.query(insert_query, job_config=job_config)
            query_job.result()
            logger.info(f"Schedule {schedule_id} persisted successfully")
        except Exception as e:
            if 'Not found: Table' in str(e):
                logger.warning("schedule_recommendations table not found, creating it")
                self._create_schedule_table()
                # Retry insert
                query_job = self.client.query(insert_query, job_config=job_config)
                query_job.result()
                logger.info(f"Schedule {schedule_id} persisted successfully after table creation")
            else:
                logger.error(f"Failed to persist schedule: {e}")
                raise

    def _create_schedule_table(self):
        """Create schedule_recommendations table if it doesn't exist."""
        schema = [
            bigquery.SchemaField("schedule_id", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("page_name", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("created_at", "TIMESTAMP", mode="REQUIRED"),
            bigquery.SchemaField("schedule_json", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("total_messages", "INTEGER"),
            bigquery.SchemaField("saturation_zone", "STRING")
        ]

        table_ref = f"{self.project_id}.{self.dataset}.schedule_recommendations"
        table = bigquery.Table(table_ref, schema=schema)
        table = self.client.create_table(table, exists_ok=True)
        logger.info(f"Created table {table_ref}")

    def _lock_caption_assignments(
        self,
        schedule_id: str,
        page_name: str,
        messages: List[Dict]
    ):
        """Call lock_caption_assignments procedure to atomically reserve captions."""
        logger.info(f"Locking {len(messages)} caption assignments for {schedule_id}")

        # Build assignments array
        assignments = []
        for msg in messages:
            if msg['message_type'] == 'PPV':  # Only lock PPV captions
                send_time = msg['scheduled_send_time']
                assignments.append({
                    'caption_id': msg['caption_id'],
                    'scheduled_send_date': send_time.date(),
                    'scheduled_send_hour': send_time.hour
                })

        if not assignments:
            logger.warning("No PPV messages to lock")
            return

        # Format as JSON array for BigQuery
        assignments_json = json.dumps(assignments, default=str)

        query = f"""
        CALL `{self.project_id}.{self.dataset}.lock_caption_assignments`(
            @schedule_id,
            @page_name,
            ARRAY(
                SELECT AS STRUCT
                    CAST(JSON_EXTRACT_SCALAR(assignment, '$.caption_id') AS INT64) AS caption_id,
                    CAST(JSON_EXTRACT_SCALAR(assignment, '$.scheduled_send_date') AS DATE) AS scheduled_send_date,
                    CAST(JSON_EXTRACT_SCALAR(assignment, '$.scheduled_send_hour') AS INT64) AS scheduled_send_hour
                FROM UNNEST(JSON_EXTRACT_ARRAY(@assignments_json)) AS assignment
            )
        );
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("schedule_id", "STRING", schedule_id),
                bigquery.ScalarQueryParameter("page_name", "STRING", page_name),
                bigquery.ScalarQueryParameter("assignments_json", "STRING", assignments_json)
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            query_job.result()
            logger.info(f"Locked {len(assignments)} caption assignments")
        except Exception as e:
            logger.error(f"Failed to lock caption assignments: {e}")
            raise

    def _build_dataframe(
        self,
        schedule_id: str,
        page_name: str,
        messages: List[Dict]
    ) -> pd.DataFrame:
        """Build pandas DataFrame for CSV export."""
        rows = []

        for msg in messages:
            send_time = msg['scheduled_send_time']

            rows.append({
                'schedule_id': schedule_id,
                'page_name': page_name,
                'day_of_week': send_time.strftime('%A'),
                'scheduled_send_time': send_time.strftime('%Y-%m-%d %H:%M:%S'),
                'message_type': msg['message_type'],
                'caption_id': msg['caption_id'],
                'caption_text': msg['caption_text'],
                'price_tier': msg['price_tier'],
                'content_category': msg['content_category'],
                'has_urgency': msg['has_urgency'],
                'performance_score': round(msg['performance_score'], 2)
            })

        return pd.DataFrame(rows)

    def export_csv(self, schedule_df: pd.DataFrame, output_path: str):
        """Export schedule DataFrame to CSV."""
        logger.info(f"Exporting schedule to {output_path}")
        schedule_df.to_csv(output_path, index=False)
        logger.info(f"CSV exported successfully: {len(schedule_df)} rows")

    def _log_export(
        self,
        schedule_id: str,
        page_name: str,
        message_count: int,
        duration: float,
        error: Optional[str]
    ):
        """Log schedule export to schedule_export_log table."""
        table_ref = f"{self.project_id}.{self.dataset}.schedule_export_log"

        insert_query = f"""
        INSERT INTO `{table_ref}` (
            schedule_id,
            page_name,
            export_timestamp,
            message_count,
            execution_time_seconds,
            error_message,
            status
        ) VALUES (
            @schedule_id,
            @page_name,
            @export_timestamp,
            @message_count,
            @execution_time,
            @error_message,
            @status
        )
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("schedule_id", "STRING", schedule_id),
                bigquery.ScalarQueryParameter("page_name", "STRING", page_name),
                bigquery.ScalarQueryParameter("export_timestamp", "TIMESTAMP", datetime.now(LA_TZ)),
                bigquery.ScalarQueryParameter("message_count", "INT64", message_count),
                bigquery.ScalarQueryParameter("execution_time", "FLOAT64", duration),
                bigquery.ScalarQueryParameter("error_message", "STRING", error),
                bigquery.ScalarQueryParameter("status", "STRING", "SUCCESS" if error is None else "FAILED")
            ]
        )

        try:
            query_job = self.client.query(insert_query, job_config=job_config)
            query_job.result()
        except Exception as e:
            if 'Not found: Table' in str(e):
                # Create table if it doesn't exist
                self._create_export_log_table()
                query_job = self.client.query(insert_query, job_config=job_config)
                query_job.result()
            else:
                logger.warning(f"Failed to log export: {e}")

    def _create_export_log_table(self):
        """Create schedule_export_log table if it doesn't exist."""
        schema = [
            bigquery.SchemaField("schedule_id", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("page_name", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("export_timestamp", "TIMESTAMP", mode="REQUIRED"),
            bigquery.SchemaField("message_count", "INTEGER"),
            bigquery.SchemaField("execution_time_seconds", "FLOAT"),
            bigquery.SchemaField("error_message", "STRING"),
            bigquery.SchemaField("status", "STRING")
        ]

        table_ref = f"{self.project_id}.{self.dataset}.schedule_export_log"
        table = bigquery.Table(table_ref, schema=schema)
        table = self.client.create_table(table, exists_ok=True)
        logger.info(f"Created table {table_ref}")


# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    """Main execution function with CLI argument parsing."""
    import argparse

    parser = argparse.ArgumentParser(description='EROS Schedule Builder')
    parser.add_argument('--page-name', required=True, help='Creator page name (e.g., jadebri)')
    parser.add_argument('--start-date', required=True, help='Schedule start date (YYYY-MM-DD)')
    parser.add_argument('--project-id', default='of-scheduler-proj', help='GCP project ID')
    parser.add_argument('--dataset', default='eros_scheduling_brain', help='BigQuery dataset')
    parser.add_argument('--output', help='Output CSV path (default: {schedule_id}.csv)')

    args = parser.parse_args()

    try:
        # Initialize builder
        builder = ScheduleBuilder(args.project_id, args.dataset)

        # Build schedule
        schedule_id, df = builder.build_schedule(args.page_name, args.start_date)

        # Export CSV
        output_path = args.output or f"{schedule_id}.csv"
        builder.export_csv(df, output_path)

        print(f"\n{'='*60}")
        print(f"Schedule {schedule_id} created successfully!")
        print(f"{'='*60}")
        print(f"Page: {args.page_name}")
        print(f"Start Date: {args.start_date}")
        print(f"Total Messages: {len(df)}")
        print(f"PPVs: {len(df[df['message_type'] == 'PPV'])}")
        print(f"Bumps: {len(df[df['message_type'] == 'Bump'])}")
        print(f"CSV: {output_path}")
        print(f"{'='*60}\n")

    except Exception as e:
        logger.error(f"Schedule build failed: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
