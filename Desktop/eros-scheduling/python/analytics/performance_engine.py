"""
EROS Performance Analysis Engine
Optimized analytics engine combining ML predictions with statistical analysis
Designed for Claude AI orchestration with Max 20x subscription
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.model_selection import train_test_split
from google.cloud import bigquery
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class PerformanceEngine:
    """
    Core analytics engine that performs heavy computational work.
    Claude AI will interpret results and make strategic decisions.
    """

    def __init__(self, project_id: str = "of-scheduler-proj"):
        self.project_id = project_id
        self.dataset_id = "eros_scheduling_brain"
        self.client = bigquery.Client(project=project_id)
        self.model = None

    def analyze_creator_comprehensive(
        self,
        page_name: str,
        lookback_days: int = 90
    ) -> Dict:
        """
        Comprehensive 90-day analysis for a creator.
        Returns raw analysis for Claude AI to interpret.
        """
        logger.info(f"Starting comprehensive analysis for {page_name}")

        # Fetch historical data
        df = self._fetch_historical_data(page_name, lookback_days)

        if df.empty:
            logger.warning(f"No data found for {page_name}")
            return self._empty_analysis(page_name)

        # Get vault content availability (CRITICAL)
        available_content = self._get_vault_content(page_name)

        # Perform all analytics
        analysis = {
            'page_name': page_name,
            'analysis_timestamp': datetime.now().isoformat(),
            'data_quality': self._assess_data_quality(df),
            'classification': self._classify_creator(df),
            'metrics': self._calculate_core_metrics(df),
            'timing_analysis': self._analyze_timing_patterns(df),
            'price_optimization': self._analyze_price_performance(df),
            'content_analysis': self._analyze_content_types(df, available_content),
            'ml_predictions': self._generate_ml_predictions(df),
            'available_content': available_content,
            'recommendations_data': self._generate_recommendation_data(df)
        }

        return analysis

    def _fetch_historical_data(
        self,
        page_name: str,
        lookback_days: int
    ) -> pd.DataFrame:
        """Fetch 90-day historical performance with exponential decay weighting"""

        query = f"""
        WITH base_data AS (
            SELECT
                mm.*,
                EXTRACT(HOUR FROM sending_time) AS hour,
                EXTRACT(DAYOFWEEK FROM sending_time) AS day_of_week,
                DATE(sending_time) AS send_date,
                DATE_DIFF(CURRENT_DATE(), DATE(sending_time), DAY) as days_old,
                CASE
                    WHEN price = 0 THEN 'free'
                    WHEN price < 10 THEN 'budget'
                    WHEN price < 20 THEN 'mid'
                    WHEN price < 30 THEN 'premium'
                    ELSE 'ultra'
                END AS price_tier,
                (viewed_count / NULLIF(sent_count, 0)) * 100 as view_rate,
                (purchased_count / NULLIF(viewed_count, 0)) * 100 as purchase_rate,
                (earnings / NULLIF(sent_count, 0)) as revenue_per_send
            FROM `{self.project_id}.{self.dataset_id}.mass_messages` mm
            WHERE page_name = '{page_name}'
                AND sending_time >= DATE_SUB(CURRENT_DATE(), INTERVAL {lookback_days} DAY)
                AND sent_count > 50
        )
        SELECT
            *,
            -- Exponential decay weight (14-21 day half-life)
            EXP(-days_old / 18.0) as decay_weight
        FROM base_data
        ORDER BY sending_time DESC
        """

        return self.client.query(query).to_dataframe()

    def _get_vault_content(self, page_name: str) -> List[str]:
        """
        CRITICAL: Get available content from vault_matrix.
        Must ALWAYS be checked before caption assignment.
        """

        query = f"""
        SELECT *
        FROM `{self.project_id}.{self.dataset_id}.vault_matrix`
        WHERE LOWER(page_name) = LOWER('{page_name}')
        """

        try:
            df = self.client.query(query).to_dataframe()
            if not df.empty:
                # Return list of content types where value is TRUE
                available = [
                    col for col in df.columns
                    if col != 'page_name' and df[col].iloc[0] == True
                ]
                logger.info(f"Available content for {page_name}: {available}")
                return available
        except Exception as e:
            logger.error(f"Failed to fetch vault matrix: {e}")

        return []

    def _assess_data_quality(self, df: pd.DataFrame) -> Dict:
        """Assess data quality for confidence scoring"""

        total_messages = len(df)
        days_span = (df['send_date'].max() - df['send_date'].min()).days
        avg_sent_count = df['sent_count'].mean()
        days_since_last = (datetime.now().date() - df['send_date'].max()).days

        # Calculate quality score (0-100)
        volume_score = min(total_messages / 100, 1.0) * 40
        freshness_score = max(1 - (days_since_last / 14), 0) * 30
        sample_size_score = min(avg_sent_count / 1000, 1.0) * 30

        quality_score = volume_score + freshness_score + sample_size_score

        return {
            'total_messages': total_messages,
            'days_span': days_span,
            'avg_sent_count': int(avg_sent_count),
            'days_since_last_message': days_since_last,
            'quality_score': round(quality_score, 1),
            'confidence_level': 'high' if quality_score > 75 else 'medium' if quality_score > 50 else 'low'
        }

    def _classify_creator(self, df: pd.DataFrame) -> Dict:
        """Classify creator tier, health, and saturation status"""

        avg_sent_count = df['sent_count'].mean()

        # Tier classification
        if avg_sent_count >= 5000:
            tier = 'ULTRA'
            saturation_threshold = 30
        elif avg_sent_count >= 2000:
            tier = 'LARGE'
            saturation_threshold = 35
        elif avg_sent_count >= 500:
            tier = 'MID'
            saturation_threshold = 40
        else:
            tier = 'SMALL'
            saturation_threshold = 45

        # Health status (revenue trend last 30 vs 60 days)
        recent_30 = df[df['days_old'] <= 30]['earnings'].sum()
        previous_30 = df[(df['days_old'] > 30) & (df['days_old'] <= 60)]['earnings'].sum()

        if previous_30 > 0:
            growth_rate = ((recent_30 - previous_30) / previous_30) * 100
        else:
            growth_rate = 0

        if growth_rate > 15:
            health = 'GROWING'
            health_multiplier = 1.2
        elif growth_rate < -15:
            health = 'DECLINING'
            health_multiplier = 0.85
        else:
            health = 'STABLE'
            health_multiplier = 1.0

        # Saturation status
        avg_view_rate = df['view_rate'].mean()

        if avg_view_rate < saturation_threshold:
            saturation = 'OVERSATURATED'
            saturation_multiplier = 0.75
        elif avg_view_rate < saturation_threshold + 10:
            saturation = 'OPTIMAL'
            saturation_multiplier = 1.0
        else:
            saturation = 'UNDERSATURATED'
            saturation_multiplier = 1.3

        return {
            'tier': tier,
            'estimated_subscribers': int(avg_sent_count),
            'health_status': health,
            'health_multiplier': health_multiplier,
            'growth_rate_pct': round(growth_rate, 1),
            'saturation_status': saturation,
            'saturation_multiplier': saturation_multiplier,
            'avg_view_rate': round(avg_view_rate, 1),
            'saturation_threshold': saturation_threshold
        }

    def _calculate_core_metrics(self, df: pd.DataFrame) -> Dict:
        """Calculate weighted core performance metrics"""

        # Apply decay weights to recent data
        weighted_earnings = (df['earnings'] * df['decay_weight']).sum()
        weighted_view_rate = (df['view_rate'] * df['decay_weight']).sum() / df['decay_weight'].sum()
        weighted_purchase_rate = (df['purchase_rate'] * df['decay_weight']).sum() / df['decay_weight'].sum()
        weighted_rps = (df['revenue_per_send'] * df['decay_weight']).sum() / df['decay_weight'].sum()

        return {
            'total_revenue_90d': float(df['earnings'].sum()),
            'weighted_revenue': float(weighted_earnings),
            'avg_daily_revenue': float(df.groupby('send_date')['earnings'].sum().mean()),
            'avg_view_rate': float(weighted_view_rate),
            'avg_purchase_rate': float(weighted_purchase_rate),
            'avg_revenue_per_send': float(weighted_rps),
            'total_messages_sent': len(df),
            'avg_price': float(df['price'].mean()),
            'median_price': float(df['price'].median()),
            'best_single_message_revenue': float(df['earnings'].max())
        }

    def _analyze_timing_patterns(self, df: pd.DataFrame) -> Dict:
        """Analyze timing patterns with weighted metrics"""

        # Hourly analysis with decay weights
        hourly = df.groupby('hour').agg({
            'earnings': lambda x: (x * df.loc[x.index, 'decay_weight']).sum(),
            'revenue_per_send': lambda x: (x * df.loc[x.index, 'decay_weight']).mean(),
            'view_rate': 'mean',
            'purchase_rate': 'mean'
        }).round(2)

        # Identify prime hours (top 75th percentile by weighted revenue)
        revenue_threshold = hourly['earnings'].quantile(0.75)
        prime_hours = hourly[hourly['earnings'] >= revenue_threshold].index.tolist()

        # Day of week analysis
        dow_performance = df.groupby('day_of_week').agg({
            'earnings': 'sum',
            'view_rate': 'mean',
            'purchase_rate': 'mean'
        }).round(2).to_dict('index')

        return {
            'prime_hours': prime_hours,
            'hourly_revenue': hourly['earnings'].to_dict(),
            'hourly_rps': hourly['revenue_per_send'].to_dict(),
            'day_of_week_performance': dow_performance,
            'optimal_daily_volume': int(df.groupby('send_date').size().quantile(0.75))
        }

    def _analyze_price_performance(self, df: pd.DataFrame) -> Dict:
        """Optimize pricing strategy (focus on revenue per send, not conversion)"""

        price_tier_analysis = df.groupby('price_tier').agg({
            'earnings': 'sum',
            'revenue_per_send': 'mean',
            'purchase_rate': 'mean',
            'view_rate': 'mean',
            'message': 'count'
        }).round(2)

        # Find sweet spot (highest RPS)
        best_tier = price_tier_analysis['revenue_per_send'].idxmax()

        # Price elasticity by hour
        hourly_pricing = {}
        for hour in df['hour'].unique():
            hour_df = df[df['hour'] == hour]
            if len(hour_df) > 5:
                hourly_pricing[int(hour)] = {
                    'optimal_price': float(hour_df[hour_df['earnings'] > 0]['price'].median()),
                    'avg_rps': float(hour_df['revenue_per_send'].mean()),
                    'best_tier': hour_df.groupby('price_tier')['revenue_per_send'].mean().idxmax()
                }

        return {
            'tier_performance': price_tier_analysis.to_dict('index'),
            'best_performing_tier': best_tier,
            'hourly_pricing': hourly_pricing,
            'recommended_price_range': {
                'budget': (5, 9),
                'mid': (10, 19),
                'premium': (20, 30),
                'ultra': (30, 50)
            }
        }

    def _analyze_content_types(
        self,
        df: pd.DataFrame,
        available_content: List[str]
    ) -> Dict:
        """Analyze content type performance with vault validation"""

        content_analysis = {
            'available_content_types': available_content,
            'restricted_content_types': []
        }

        # Analyze by message type if available
        if 'message_type' in df.columns:
            type_performance = df.groupby('message_type').agg({
                'earnings': ['sum', 'mean'],
                'purchase_rate': 'mean',
                'message': 'count'
            }).round(2)

            content_analysis['type_performance'] = type_performance.to_dict()

        return content_analysis

    def _generate_ml_predictions(self, df: pd.DataFrame) -> Dict:
        """Generate ML-based revenue predictions"""

        try:
            # Prepare features
            X = pd.DataFrame()
            X['hour'] = df['hour']
            X['day_of_week'] = df['day_of_week']
            X['hour_sin'] = np.sin(2 * np.pi * df['hour'] / 24)
            X['hour_cos'] = np.cos(2 * np.pi * df['hour'] / 24)
            X['price'] = df['price']
            X['price_squared'] = df['price'] ** 2
            X['is_free'] = (df['price'] == 0).astype(int)
            X['avg_hour_revenue'] = df.groupby('hour')['earnings'].transform('mean')

            y = df['earnings']

            if len(X) < 30:
                return {'error': 'Insufficient data for ML predictions'}

            # Train model
            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=0.2, random_state=42
            )

            model = GradientBoostingRegressor(n_estimators=100, random_state=42)
            model.fit(X_train, y_train)

            # Feature importance
            feature_importance = pd.DataFrame({
                'feature': X.columns,
                'importance': model.feature_importances_
            }).sort_values('importance', ascending=False)

            # Test accuracy
            train_score = model.score(X_train, y_train)
            test_score = model.score(X_test, y_test)

            self.model = model  # Store for later use

            return {
                'model_type': 'GradientBoostingRegressor',
                'train_accuracy': round(train_score * 100, 1),
                'test_accuracy': round(test_score * 100, 1),
                'feature_importance': feature_importance.head(5).to_dict('records'),
                'model_trained': True
            }

        except Exception as e:
            logger.error(f"ML prediction failed: {e}")
            return {'error': str(e), 'model_trained': False}

    def _generate_recommendation_data(self, df: pd.DataFrame) -> Dict:
        """Generate data for Claude AI to create recommendations"""

        # Identify patterns for Claude to interpret
        urgency_words = ['tonight', 'now', 'limited', 'exclusive', 'urgent']
        urgency_performance = []

        for word in urgency_words:
            if 'message' in df.columns:
                has_word = df['message'].str.lower().str.contains(word, na=False)
                if has_word.sum() > 3:
                    avg_earnings = df[has_word]['earnings'].mean()
                    baseline = df[~has_word]['earnings'].mean()
                    if baseline > 0:
                        lift = ((avg_earnings - baseline) / baseline) * 100
                        urgency_performance.append({
                            'word': word,
                            'lift_pct': round(lift, 1),
                            'sample_size': int(has_word.sum())
                        })

        # Message length analysis
        if 'message' in df.columns:
            df['message_length'] = df['message'].str.len()
            length_bins = pd.cut(df['message_length'], bins=[0, 50, 100, 150, 300], labels=['very_short', 'short', 'medium', 'long'])
            length_performance = df.groupby(length_bins)['revenue_per_send'].mean().to_dict()
        else:
            length_performance = {}

        return {
            'urgency_signals': urgency_performance,
            'length_performance': length_performance,
            'patterns_for_ai_interpretation': {
                'ready_for_claude': True,
                'complexity': 'moderate'
            }
        }

    def _empty_analysis(self, page_name: str) -> Dict:
        """Return empty analysis structure when no data"""
        return {
            'page_name': page_name,
            'analysis_timestamp': datetime.now().isoformat(),
            'error': 'No data available for analysis',
            'data_quality': {'quality_score': 0, 'confidence_level': 'none'}
        }


if __name__ == "__main__":
    # Test
    engine = PerformanceEngine()
    result = engine.analyze_creator_comprehensive("mayahill")
    print(f"Analysis completed. Quality score: {result['data_quality']['quality_score']}")
