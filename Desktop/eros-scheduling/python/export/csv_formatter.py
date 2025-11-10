"""
CSV Schedule Template Formatter
Exports 7-day schedules in human-readable CSV format for Google Sheets
"""

import pandas as pd
from typing import List, Dict
from datetime import date, datetime, timedelta
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ScheduleCSVFormatter:
    """Format schedule templates for Google Sheets upload"""

    @staticmethod
    def format_7_day_schedule(
        page_name: str,
        schedule_data: List[Dict],
        start_date: date
    ) -> pd.DataFrame:
        """
        Format schedule data into CSV-ready DataFrame.

        Args:
            page_name: Creator username
            schedule_data: List of scheduled messages
            start_date: Week start date

        Returns:
            DataFrame ready for CSV export
        """

        if not schedule_data:
            return pd.DataFrame()

        formatted_rows = []

        for msg in schedule_data:
            # Add randomized minutes for natural feel
            minutes = pd.np.random.randint(0, 60)

            formatted_rows.append({
                'Page': page_name,
                'Day': msg.get('day_name', 'Monday'),
                'Date': msg.get('send_date', start_date).strftime('%Y-%m-%d'),
                'Time': f"{msg.get('hour', 12):02d}:{minutes:02d}",
                'Type': msg.get('message_type', 'PPV').replace('_', ' ').title(),
                'Caption': msg.get('caption_text', '')[:200],  # Limit length
                'Price': f"${msg.get('price', 0):.2f}" if msg.get('price', 0) > 0 else "FREE",
                'Expected_Revenue': f"${msg.get('expected_revenue', 0):.2f}",
                'Content_Category': msg.get('content_category', 'General'),
                'Strategy_Note': msg.get('strategy_notes', ''),
                'Confidence': f"{msg.get('confidence_score', 0.5):.0%}"
            })

        df = pd.DataFrame(formatted_rows)

        # Sort by date and time
        df = df.sort_values(['Date', 'Time'])

        return df

    @staticmethod
    def export_to_csv(
        page_name: str,
        schedule_data: List[Dict],
        start_date: date,
        output_path: str
    ) -> str:
        """
        Export schedule to CSV file.

        Args:
            page_name: Creator username
            schedule_data: List of scheduled messages
            start_date: Week start date
            output_path: File path for CSV

        Returns:
            Path to created file
        """

        df = ScheduleCSVFormatter.format_7_day_schedule(
            page_name,
            schedule_data,
            start_date
        )

        if df.empty:
            logger.warning(f"No data to export for {page_name}")
            return None

        # Export to CSV
        df.to_csv(output_path, index=False)

        logger.info(f"Exported {len(df)} messages to {output_path}")

        return output_path

    @staticmethod
    def create_summary_row(schedule_data: List[Dict]) -> Dict:
        """Create summary statistics row for CSV"""

        if not schedule_data:
            return {}

        total_messages = len(schedule_data)
        total_expected_revenue = sum(msg.get('expected_revenue', 0) for msg in schedule_data)
        avg_price = sum(msg.get('price', 0) for msg in schedule_data) / total_messages
        ppv_count = sum(1 for msg in schedule_data if msg.get('price', 0) > 0)
        free_count = total_messages - ppv_count

        return {
            'Page': 'SUMMARY',
            'Day': '',
            'Date': '',
            'Time': '',
            'Type': f"{total_messages} messages",
            'Caption': f"{ppv_count} PPVs, {free_count} Free",
            'Price': f"Avg: ${avg_price:.2f}",
            'Expected_Revenue': f"Total: ${total_expected_revenue:.2f}",
            'Content_Category': '',
            'Strategy_Note': f"Estimated weekly revenue",
            'Confidence': ''
        }


class MultiCreatorCSVExporter:
    """Export schedules for multiple creators"""

    @staticmethod
    def export_all_creators(
        creator_schedules: Dict[str, List[Dict]],
        start_date: date,
        output_dir: str
    ) -> List[str]:
        """
        Export CSV files for all creators.

        Args:
            creator_schedules: Dict mapping page_name to schedule data
            start_date: Week start date
            output_dir: Directory for output files

        Returns:
            List of created file paths
        """

        created_files = []

        for page_name, schedule_data in creator_schedules.items():
            # Create filename
            filename = f"{output_dir}/{page_name}_{start_date.strftime('%Y%m%d')}_schedule.csv"

            # Export
            try:
                path = ScheduleCSVFormatter.export_to_csv(
                    page_name,
                    schedule_data,
                    start_date,
                    filename
                )

                if path:
                    created_files.append(path)

            except Exception as e:
                logger.error(f"Failed to export {page_name}: {e}")

        logger.info(f"Created {len(created_files)} CSV files")

        return created_files

    @staticmethod
    def create_master_summary(
        creator_schedules: Dict[str, List[Dict]],
        output_path: str
    ) -> str:
        """
        Create master summary CSV with all creators.

        Args:
            creator_schedules: Dict mapping page_name to schedule data
            output_path: File path for summary CSV

        Returns:
            Path to created file
        """

        summary_rows = []

        for page_name, schedule_data in creator_schedules.items():
            if not schedule_data:
                continue

            total_messages = len(schedule_data)
            total_revenue = sum(msg.get('expected_revenue', 0) for msg in schedule_data)
            ppv_count = sum(1 for msg in schedule_data if msg.get('price', 0) > 0)

            summary_rows.append({
                'Page_Name': page_name,
                'Total_Messages': total_messages,
                'PPV_Messages': ppv_count,
                'Free_Messages': total_messages - ppv_count,
                'Expected_Weekly_Revenue': f"${total_revenue:.2f}",
                'Avg_Revenue_Per_Message': f"${total_revenue / total_messages:.2f}",
                'Status': 'Ready for Review'
            })

        df = pd.DataFrame(summary_rows)
        df = df.sort_values('Expected_Weekly_Revenue', ascending=False)

        df.to_csv(output_path, index=False)

        logger.info(f"Created master summary: {output_path}")

        return output_path


if __name__ == "__main__":
    # Test
    test_schedule = [
        {
            'day_name': 'Monday',
            'send_date': date.today(),
            'hour': 10,
            'message_type': 'solo',
            'caption_text': 'Just filmed something special... 💦',
            'price': 15.0,
            'expected_revenue': 450.0,
            'content_category': 'Solo',
            'strategy_notes': 'Morning engagement driver',
            'confidence_score': 0.85
        },
        {
            'day_name': 'Monday',
            'send_date': date.today(),
            'hour': 18,
            'message_type': 'boy_girl',
            'caption_text': 'Raw and uncut BG content 🔥',
            'price': 25.0,
            'expected_revenue': 625.0,
            'content_category': 'BG',
            'strategy_notes': 'Evening premium content',
            'confidence_score': 0.90
        }
    ]

    df = ScheduleCSVFormatter.format_7_day_schedule(
        'mayahill',
        test_schedule,
        date.today()
    )

    print(df.to_string(index=False))
