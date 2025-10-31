#!/usr/bin/env python3
"""
Test script for Schedule Builder
=================================
Demonstrates schedule builder usage with sample data.
"""

from schedule_builder import ScheduleBuilder
from datetime import datetime
from zoneinfo import ZoneInfo
import json

LA_TZ = ZoneInfo("America/Los_Angeles")

def test_schedule_builder():
    """Test schedule builder with sample creator."""

    print("="*80)
    print("EROS Schedule Builder - Test Execution")
    print("="*80)
    print()

    # Initialize builder
    project_id = "of-scheduler-proj"
    dataset = "eros_scheduling_brain"

    print(f"Project: {project_id}")
    print(f"Dataset: {dataset}")
    print()

    builder = ScheduleBuilder(project_id, dataset)

    # Test parameters
    page_name = "jadebri"
    start_date = "2025-11-04"  # Monday

    print(f"Building schedule for: {page_name}")
    print(f"Start date: {start_date}")
    print()

    try:
        # Build schedule
        schedule_id, df = builder.build_schedule(page_name, start_date)

        # Display results
        print("\n" + "="*80)
        print("SCHEDULE BUILT SUCCESSFULLY")
        print("="*80)
        print(f"\nSchedule ID: {schedule_id}")
        print(f"Total Messages: {len(df)}")
        print(f"PPVs: {len(df[df['message_type'] == 'PPV'])}")
        print(f"Bumps: {len(df[df['message_type'] == 'Bump'])}")
        print()

        # Display schedule breakdown by day
        print("\nSchedule Breakdown by Day:")
        print("-" * 80)
        for day in df['day_of_week'].unique():
            day_df = df[df['day_of_week'] == day]
            ppv_count = len(day_df[day_df['message_type'] == 'PPV'])
            bump_count = len(day_df[day_df['message_type'] == 'Bump'])
            print(f"{day:10s}: {len(day_df):2d} messages ({ppv_count} PPV, {bump_count} Bump)")

        # Display sample messages
        print("\nFirst 5 Messages:")
        print("-" * 80)
        print(df.head(5).to_string(index=False))

        # Export CSV
        output_path = f"{schedule_id}.csv"
        builder.export_csv(df, output_path)
        print(f"\nCSV exported to: {output_path}")

        # Display price tier distribution
        print("\nPrice Tier Distribution:")
        print("-" * 80)
        tier_counts = df[df['message_type'] == 'PPV']['price_tier'].value_counts()
        for tier, count in tier_counts.items():
            print(f"{tier:10s}: {count:2d} messages")

        print("\n" + "="*80)
        print("TEST COMPLETED SUCCESSFULLY")
        print("="*80)

    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

    return True


def test_volume_calculations():
    """Test volume calculation logic for different account sizes and saturation levels."""

    print("\n" + "="*80)
    print("VOLUME CALCULATION TESTS")
    print("="*80)

    builder = ScheduleBuilder("of-scheduler-proj", "eros_scheduling_brain")

    test_cases = [
        ("MICRO", 0.2, "GREEN"),
        ("SMALL", 0.2, "GREEN"),
        ("MEDIUM", 0.4, "YELLOW"),
        ("LARGE", 0.7, "RED"),
        ("MEGA", 0.8, "RED"),
    ]

    print("\n{:10s} {:10s} {:15s} {:10s} {:10s}".format(
        "Account", "Saturation", "Zone", "PPVs", "Bumps"
    ))
    print("-" * 80)

    for account_size, sat_score, expected_zone in test_cases:
        ppv_count, bump_count, zone = builder.calculate_volume_targets(
            account_size, sat_score, saturation_tolerance=0.5
        )

        status = "✓" if zone == expected_zone else "✗"
        print(f"{account_size:10s} {sat_score:10.2f} {zone:15s} {ppv_count:10d} {bump_count:10d} {status}")

    print()


def create_sample_csv():
    """Create a sample CSV with expected format."""

    print("\n" + "="*80)
    print("SAMPLE CSV OUTPUT")
    print("="*80)

    sample_data = [
        {
            'schedule_id': 'sched_20251031_000000_jadebri',
            'page_name': 'jadebri',
            'day_of_week': 'Monday',
            'scheduled_send_time': '2025-11-04 10:00:00',
            'message_type': 'PPV',
            'caption_id': 12345,
            'caption_text': 'Check your DMs 💌',
            'price_tier': 'Premium',
            'content_category': 'Tease/Preview',
            'has_urgency': True,
            'performance_score': 0.87
        },
        {
            'schedule_id': 'sched_20251031_000000_jadebri',
            'page_name': 'jadebri',
            'day_of_week': 'Monday',
            'scheduled_send_time': '2025-11-04 13:30:00',
            'message_type': 'Bump',
            'caption_id': 12346,
            'caption_text': 'Good afternoon babe 💕',
            'price_tier': 'Free',
            'content_category': 'Engagement',
            'has_urgency': False,
            'performance_score': 0.0
        },
        {
            'schedule_id': 'sched_20251031_000000_jadebri',
            'page_name': 'jadebri',
            'day_of_week': 'Monday',
            'scheduled_send_time': '2025-11-04 17:15:00',
            'message_type': 'PPV',
            'caption_id': 12347,
            'caption_text': 'Just posted something special... 🔥',
            'price_tier': 'Mid',
            'content_category': 'Full Explicit',
            'has_urgency': False,
            'performance_score': 0.72
        },
    ]

    import pandas as pd
    df = pd.DataFrame(sample_data)

    print("\nSample CSV Format:")
    print("-" * 80)
    print(df.to_string(index=False))

    # Write sample
    sample_path = "sample_schedule_output.csv"
    df.to_csv(sample_path, index=False)
    print(f"\nSample CSV saved to: {sample_path}")
    print()


if __name__ == "__main__":
    print("\nEROS Schedule Builder - Test Suite")
    print("===================================\n")

    # Test volume calculations (doesn't require BigQuery connection)
    test_volume_calculations()

    # Create sample CSV
    create_sample_csv()

    # Full integration test (requires BigQuery connection and data)
    print("\nTo run full integration test with BigQuery:")
    print("  python test_schedule_builder.py --integration")
    print("\nNote: This requires:")
    print("  1. Valid GCP credentials")
    print("  2. Access to of-scheduler-proj.eros_scheduling_brain")
    print("  3. Existing creator data for 'jadebri' or specified page")
    print()
