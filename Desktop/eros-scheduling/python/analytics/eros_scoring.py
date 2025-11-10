"""
Unified EROS Scoring System
Single metric to track creator performance and schedule effectiveness
"""

import pandas as pd
from typing import Dict
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class EROSScoring:
    """
    EROS Score = (Revenue Per Send × 0.4) +
                  (Conversion Rate × 0.3) +
                  (Execution Rate × 0.2) +
                  (Caption Diversity × 0.1)

    Score Range: 0-100
    - Elite: 80-100
    - High: 60-79
    - Standard: 40-59
    - Needs Improvement: 20-39
    - Critical: 0-19
    """

    @staticmethod
    def calculate_eros_score(
        revenue_per_send: float,
        conversion_rate: float,
        execution_rate: float,
        caption_diversity: float
    ) -> Dict:
        """
        Calculate unified EROS score.

        Args:
            revenue_per_send: Average revenue per message sent (normalize to 0-100)
            conversion_rate: Purchase rate percentage (0-100)
            execution_rate: Percentage of scheduled messages actually sent (0-100)
            caption_diversity: Caption variety score (0-1.0)

        Returns:
            Dict with score, tier, and breakdown
        """

        # Normalize revenue_per_send to 0-100 scale
        # Assume $5 RPS = 100 score (top performer)
        rps_score = min((revenue_per_send / 5.0) * 100, 100)

        # Conversion rate is already 0-100
        conversion_score = min(conversion_rate * 100, 100)  # Convert decimal to percentage if needed

        # Execution rate is already 0-100
        execution_score = execution_rate

        # Caption diversity is 0-1, convert to 0-100
        diversity_score = caption_diversity * 100

        # Calculate weighted EROS score
        eros_score = (
            rps_score * 0.4 +
            conversion_score * 0.3 +
            execution_score * 0.2 +
            diversity_score * 0.1
        )

        # Determine tier
        if eros_score >= 80:
            tier = 'Elite'
            status = 'Exceptional performance'
        elif eros_score >= 60:
            tier = 'High'
            status = 'Strong performance'
        elif eros_score >= 40:
            tier = 'Standard'
            status = 'Average performance'
        elif eros_score >= 20:
            tier = 'Needs Improvement'
            status = 'Below target'
        else:
            tier = 'Critical'
            status = 'Immediate attention required'

        return {
            'eros_score': round(eros_score, 1),
            'tier': tier,
            'status': status,
            'breakdown': {
                'revenue_per_send_score': round(rps_score, 1),
                'conversion_score': round(conversion_score, 1),
                'execution_score': round(execution_score, 1),
                'diversity_score': round(diversity_score, 1)
            },
            'weights': {
                'revenue_per_send': 0.4,
                'conversion_rate': 0.3,
                'execution_rate': 0.2,
                'caption_diversity': 0.1
            }
        }

    @staticmethod
    def calculate_from_metrics(metrics: Dict) -> Dict:
        """
        Calculate EROS score from standard metrics dictionary.

        Expected metrics keys:
        - avg_revenue_per_send
        - avg_purchase_rate
        - execution_rate (optional, defaults to 100%)
        - caption_diversity (optional, defaults to 0.8)
        """

        rps = metrics.get('avg_revenue_per_send', 0)
        conversion = metrics.get('avg_purchase_rate', 0)
        execution = metrics.get('execution_rate', 100)
        diversity = metrics.get('caption_diversity', 0.8)

        return EROSScoring.calculate_eros_score(
            revenue_per_send=rps,
            conversion_rate=conversion,
            execution_rate=execution,
            caption_diversity=diversity
        )

    @staticmethod
    def compare_schedules(
        predicted_metrics: Dict,
        actual_metrics: Dict
    ) -> Dict:
        """
        Compare predicted vs actual EROS scores.
        Useful for measuring schedule effectiveness.
        """

        predicted_score = EROSScoring.calculate_from_metrics(predicted_metrics)
        actual_score = EROSScoring.calculate_from_metrics(actual_metrics)

        score_diff = actual_score['eros_score'] - predicted_score['eros_score']

        return {
            'predicted': predicted_score,
            'actual': actual_score,
            'score_difference': round(score_diff, 1),
            'performance_vs_prediction': 'exceeded' if score_diff > 0 else 'missed',
            'accuracy': round(100 - abs(score_diff), 1)
        }

    @staticmethod
    def get_improvement_recommendations(eros_result: Dict) -> List[str]:
        """
        Generate recommendations based on EROS score breakdown.
        Returns prioritized list of improvements.
        """

        recommendations = []
        breakdown = eros_result['breakdown']

        # Check each component
        if breakdown['revenue_per_send_score'] < 40:
            recommendations.append({
                'priority': 'HIGH',
                'component': 'Revenue Per Send',
                'recommendation': 'Focus on higher-priced content and better timing. Current RPS is below target.',
                'expected_impact': '+10-15 points'
            })

        if breakdown['conversion_score'] < 40:
            recommendations.append({
                'priority': 'HIGH',
                'component': 'Conversion Rate',
                'recommendation': 'Improve caption quality and content-caption matching. Test urgency signals.',
                'expected_impact': '+8-12 points'
            })

        if breakdown['execution_score'] < 90:
            recommendations.append({
                'priority': 'CRITICAL',
                'component': 'Execution Rate',
                'recommendation': 'Ensure all scheduled messages are sent. Low execution directly impacts revenue.',
                'expected_impact': '+5-10 points'
            })

        if breakdown['diversity_score'] < 60:
            recommendations.append({
                'priority': 'MEDIUM',
                'component': 'Caption Diversity',
                'recommendation': 'Increase caption variety to prevent subscriber fatigue.',
                'expected_impact': '+3-5 points'
            })

        # Sort by priority
        priority_order = {'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3}
        recommendations.sort(key=lambda x: priority_order[x['priority']])

        return recommendations


class AgencyDashboard:
    """Agency-wide EROS scoring for all creators"""

    @staticmethod
    def calculate_agency_score(creator_scores: List[Dict]) -> Dict:
        """
        Calculate weighted agency-wide EROS score.

        Args:
            creator_scores: List of dicts with 'page_name', 'eros_score', 'revenue'

        Returns:
            Agency-level metrics
        """

        if not creator_scores:
            return {'error': 'No creator data'}

        total_revenue = sum(c.get('revenue', 0) for c in creator_scores)

        # Weight scores by revenue contribution
        weighted_scores = []
        for creator in creator_scores:
            weight = creator.get('revenue', 0) / total_revenue if total_revenue > 0 else 1.0 / len(creator_scores)
            weighted_scores.append(creator['eros_score'] * weight)

        agency_score = sum(weighted_scores)

        # Calculate distribution
        elite_count = sum(1 for c in creator_scores if c['eros_score'] >= 80)
        high_count = sum(1 for c in creator_scores if 60 <= c['eros_score'] < 80)
        standard_count = sum(1 for c in creator_scores if 40 <= c['eros_score'] < 60)
        low_count = sum(1 for c in creator_scores if c['eros_score'] < 40)

        return {
            'agency_eros_score': round(agency_score, 1),
            'total_creators': len(creator_scores),
            'distribution': {
                'elite': elite_count,
                'high': high_count,
                'standard': standard_count,
                'needs_improvement': low_count
            },
            'top_performers': sorted(
                creator_scores,
                key=lambda x: x['eros_score'],
                reverse=True
            )[:5],
            'needs_attention': sorted(
                creator_scores,
                key=lambda x: x['eros_score']
            )[:5]
        }


if __name__ == "__main__":
    # Test
    metrics = {
        'avg_revenue_per_send': 2.50,  # $2.50 per message
        'avg_purchase_rate': 2.5,       # 2.5% conversion
        'execution_rate': 97.0,         # 97% execution
        'caption_diversity': 0.85       # 85% diversity
    }

    result = EROSScoring.calculate_from_metrics(metrics)

    print(f"EROS Score: {result['eros_score']}")
    print(f"Tier: {result['tier']}")
    print(f"Status: {result['status']}")
    print("\nBreakdown:")
    for component, score in result['breakdown'].items():
        print(f"  {component}: {score}")

    # Get recommendations
    recommendations = EROSScoring.get_improvement_recommendations(result)
    print(f"\nRecommendations: {len(recommendations)}")
    for rec in recommendations:
        print(f"  [{rec['priority']}] {rec['component']}: {rec['recommendation']}")
