"""
Analysis Overview Report Generator
Creates human-readable analysis summaries for each creator
"""

from typing import Dict
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class AnalysisReportGenerator:
    """Generate comprehensive analysis reports for Claude AI output"""

    @staticmethod
    def generate_text_report(
        page_name: str,
        analysis_data: Dict
    ) -> str:
        """
        Generate formatted text report from analysis data.

        Args:
            page_name: Creator username
            analysis_data: Output from PerformanceEngine

        Returns:
            Formatted text report
        """

        if 'error' in analysis_data:
            return f"ERROR: Unable to analyze {page_name} - {analysis_data['error']}"

        report_lines = []

        # Header
        report_lines.append("=" * 80)
        report_lines.append(f"EROS PERFORMANCE ANALYSIS REPORT")
        report_lines.append(f"Creator: {page_name.upper()}")
        report_lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report_lines.append("=" * 80)
        report_lines.append("")

        # Data Quality
        dq = analysis_data.get('data_quality', {})
        report_lines.append("📊 DATA QUALITY")
        report_lines.append(f"  Quality Score: {dq.get('quality_score', 0)}/100 ({dq.get('confidence_level', 'unknown')})")
        report_lines.append(f"  Total Messages Analyzed: {dq.get('total_messages', 0)}")
        report_lines.append(f"  Time Span: {dq.get('days_span', 0)} days")
        report_lines.append(f"  Avg Subscribers Reached: {dq.get('avg_sent_count', 0):,}")
        report_lines.append("")

        # Classification
        cls = analysis_data.get('classification', {})
        report_lines.append("🎯 CREATOR CLASSIFICATION")
        report_lines.append(f"  Tier: {cls.get('tier', 'UNKNOWN')} ({cls.get('estimated_subscribers', 0):,} subscribers)")
        report_lines.append(f"  Health Status: {cls.get('health_status', 'UNKNOWN')} (Growth: {cls.get('growth_rate_pct', 0):+.1f}%)")
        report_lines.append(f"  Saturation: {cls.get('saturation_status', 'UNKNOWN')} (View Rate: {cls.get('avg_view_rate', 0):.1f}%)")
        report_lines.append("")

        # Core Metrics
        metrics = analysis_data.get('metrics', {})
        report_lines.append("💰 PERFORMANCE METRICS (90-Day)")
        report_lines.append(f"  Total Revenue: ${metrics.get('total_revenue_90d', 0):,.2f}")
        report_lines.append(f"  Avg Daily Revenue: ${metrics.get('avg_daily_revenue', 0):,.2f}")
        report_lines.append(f"  Avg Revenue Per Send: ${metrics.get('avg_revenue_per_send', 0):.2f}")
        report_lines.append(f"  Avg View Rate: {metrics.get('avg_view_rate', 0):.1f}%")
        report_lines.append(f"  Avg Purchase Rate: {metrics.get('avg_purchase_rate', 0):.2f}%")
        report_lines.append(f"  Best Single Message: ${metrics.get('best_single_message_revenue', 0):,.2f}")
        report_lines.append("")

        # Timing Analysis
        timing = analysis_data.get('timing_analysis', {})
        prime_hours = timing.get('prime_hours', [])
        report_lines.append("⏰ OPTIMAL TIMING")
        report_lines.append(f"  Prime Hours: {', '.join(f'{h:02d}:00' for h in prime_hours)}")
        report_lines.append(f"  Recommended Daily Volume: {timing.get('optimal_daily_volume', 0)} messages")
        report_lines.append("")

        # Price Optimization
        pricing = analysis_data.get('price_optimization', {})
        report_lines.append("💵 PRICE OPTIMIZATION")
        best_tier = pricing.get('best_performing_tier', 'mid')
        report_lines.append(f"  Best Performing Tier: {best_tier.upper()}")

        tier_perf = pricing.get('tier_performance', {})
        for tier, stats in tier_perf.items():
            if tier != 'index':
                rps = stats.get('revenue_per_send', 0) if isinstance(stats, dict) else 0
                report_lines.append(f"    {tier}: ${rps:.2f} RPS")
        report_lines.append("")

        # Content Analysis
        content = analysis_data.get('content_analysis', {})
        available_content = content.get('available_content_types', [])
        report_lines.append("🎬 CONTENT AVAILABILITY")
        if available_content:
            report_lines.append(f"  Available: {', '.join(available_content)}")
        else:
            report_lines.append("  ⚠️  WARNING: No vault_matrix data found!")
        report_lines.append("")

        # ML Predictions
        ml = analysis_data.get('ml_predictions', {})
        if ml.get('model_trained'):
            report_lines.append("🤖 ML MODEL PERFORMANCE")
            report_lines.append(f"  Model: {ml.get('model_type', 'Unknown')}")
            report_lines.append(f"  Training Accuracy: {ml.get('train_accuracy', 0):.1f}%")
            report_lines.append(f"  Test Accuracy: {ml.get('test_accuracy', 0):.1f}%")
            report_lines.append("")

        # Recommendations Data
        rec_data = analysis_data.get('recommendations_data', {})
        urgency_signals = rec_data.get('urgency_signals', [])

        if urgency_signals:
            report_lines.append("🔥 URGENCY SIGNAL PERFORMANCE")
            for signal in urgency_signals[:5]:
                word = signal.get('word', '')
                lift = signal.get('lift_pct', 0)
                report_lines.append(f"  '{word}': {lift:+.1f}% lift")
            report_lines.append("")

        # Footer
        report_lines.append("=" * 80)
        report_lines.append("Report generated by EROS Max AI System")
        report_lines.append("Ready for Claude AI strategic interpretation")
        report_lines.append("=" * 80)

        return "\n".join(report_lines)

    @staticmethod
    def save_report(
        page_name: str,
        analysis_data: Dict,
        output_path: str
    ) -> str:
        """
        Generate and save report to file.

        Args:
            page_name: Creator username
            analysis_data: Analysis output
            output_path: File path

        Returns:
            Path to saved file
        """

        report_text = AnalysisReportGenerator.generate_text_report(
            page_name,
            analysis_data
        )

        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(report_text)

        logger.info(f"Saved analysis report to {output_path}")

        return output_path

    @staticmethod
    def generate_executive_summary(
        page_name: str,
        analysis_data: Dict
    ) -> str:
        """
        Generate brief executive summary (for quick review).

        Args:
            page_name: Creator username
            analysis_data: Analysis output

        Returns:
            Brief summary text
        """

        if 'error' in analysis_data:
            return f"{page_name}: ERROR - {analysis_data['error']}"

        cls = analysis_data.get('classification', {})
        metrics = analysis_data.get('metrics', {})

        summary = f"""
{page_name.upper()} - Quick Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Tier: {cls.get('tier', '?')} | Health: {cls.get('health_status', '?')} | Saturation: {cls.get('saturation_status', '?')}
90-Day Revenue: ${metrics.get('total_revenue_90d', 0):,.0f}
Avg Daily: ${metrics.get('avg_daily_revenue', 0):.0f} | RPS: ${metrics.get('avg_revenue_per_send', 0):.2f}
View Rate: {metrics.get('avg_view_rate', 0):.1f}% | Purchase Rate: {metrics.get('avg_purchase_rate', 0):.2f}%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """.strip()

        return summary


if __name__ == "__main__":
    # Test
    test_data = {
        'data_quality': {
            'quality_score': 85.3,
            'confidence_level': 'high',
            'total_messages': 342,
            'days_span': 90,
            'avg_sent_count': 4250
        },
        'classification': {
            'tier': 'LARGE',
            'estimated_subscribers': 4250,
            'health_status': 'GROWING',
            'growth_rate_pct': 18.5,
            'saturation_status': 'OPTIMAL',
            'avg_view_rate': 42.3
        },
        'metrics': {
            'total_revenue_90d': 52340.50,
            'avg_daily_revenue': 581.56,
            'avg_revenue_per_send': 2.85,
            'avg_view_rate': 42.3,
            'avg_purchase_rate': 2.8,
            'best_single_message_revenue': 1250.00
        },
        'timing_analysis': {
            'prime_hours': [10, 14, 18, 21],
            'optimal_daily_volume': 9
        },
        'price_optimization': {
            'best_performing_tier': 'mid',
            'tier_performance': {
                'budget': {'revenue_per_send': 1.85},
                'mid': {'revenue_per_send': 3.25},
                'premium': {'revenue_per_send': 4.10}
            }
        },
        'content_analysis': {
            'available_content_types': ['Solo', 'BJ', 'BG', 'Tease']
        },
        'ml_predictions': {
            'model_trained': True,
            'model_type': 'GradientBoostingRegressor',
            'train_accuracy': 96.2,
            'test_accuracy': 94.3
        },
        'recommendations_data': {
            'urgency_signals': [
                {'word': 'tonight', 'lift_pct': 23.4},
                {'word': 'exclusive', 'lift_pct': 18.2}
            ]
        }
    }

    report = AnalysisReportGenerator.generate_text_report('mayahill', test_data)
    print(report)

    print("\n\n")

    summary = AnalysisReportGenerator.generate_executive_summary('mayahill', test_data)
    print(summary)
