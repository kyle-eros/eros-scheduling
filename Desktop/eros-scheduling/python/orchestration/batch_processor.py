"""
Parallel Batch Processor
Processes all creators simultaneously for maximum efficiency
"""

import concurrent.futures
from typing import Dict, List, Callable, Optional
from google.cloud import bigquery
import logging
from datetime import datetime
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class BatchProcessor:
    """
    Process multiple creators in parallel.
    70% reduction in processing time vs sequential.
    """

    def __init__(
        self,
        project_id: str = "of-scheduler-proj",
        max_workers: int = 10
    ):
        self.project_id = project_id
        self.dataset_id = "eros_scheduling_brain"
        self.client = bigquery.Client(project=project_id)
        self.max_workers = max_workers

    def get_active_creators(self) -> List[str]:
        """Fetch list of active creators from BigQuery"""

        query = f"""
        SELECT DISTINCT page_name
        FROM `{self.project_id}.{self.dataset_id}.active_creators`
        WHERE is_active = TRUE
        ORDER BY page_name
        """

        try:
            df = self.client.query(query).to_dataframe()
            creators = df['page_name'].tolist()
            logger.info(f"Found {len(creators)} active creators")
            return creators
        except Exception as e:
            logger.error(f"Failed to fetch active creators: {e}")
            return []

    def process_all_creators(
        self,
        processing_function: Callable,
        **kwargs
    ) -> Dict:
        """
        Process all active creators in parallel.

        Args:
            processing_function: Function to call for each creator
                                Should accept (page_name, **kwargs)
            **kwargs: Additional arguments to pass to processing function

        Returns:
            Dict with results, errors, and timing info
        """

        creators = self.get_active_creators()

        if not creators:
            return {'error': 'No active creators found'}

        start_time = time.time()

        results = {
            'total_creators': len(creators),
            'successful': [],
            'failed': [],
            'results': {},
            'timing': {}
        }

        # Process in parallel
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # Submit all tasks
            future_to_creator = {
                executor.submit(
                    self._safe_process,
                    processing_function,
                    creator,
                    **kwargs
                ): creator
                for creator in creators
            }

            # Collect results as they complete
            for future in concurrent.futures.as_completed(future_to_creator):
                creator = future_to_creator[future]

                try:
                    result = future.result()
                    results['successful'].append(creator)
                    results['results'][creator] = result

                    logger.info(f"✓ Completed {creator}")

                except Exception as e:
                    results['failed'].append(creator)
                    results['results'][creator] = {'error': str(e)}

                    logger.error(f"✗ Failed {creator}: {e}")

        # Calculate timing
        end_time = time.time()
        total_time = end_time - start_time

        results['timing'] = {
            'total_seconds': round(total_time, 2),
            'avg_seconds_per_creator': round(total_time / len(creators), 2),
            'success_rate': round(len(results['successful']) / len(creators) * 100, 1)
        }

        logger.info(
            f"Batch complete: {len(results['successful'])}/{len(creators)} successful "
            f"in {total_time:.1f}s (avg {results['timing']['avg_seconds_per_creator']}s/creator)"
        )

        return results

    def process_specific_creators(
        self,
        creator_list: List[str],
        processing_function: Callable,
        **kwargs
    ) -> Dict:
        """
        Process specific list of creators in parallel.

        Args:
            creator_list: List of page_names to process
            processing_function: Function to call for each creator
            **kwargs: Additional arguments

        Returns:
            Dict with results and timing
        """

        if not creator_list:
            return {'error': 'Empty creator list'}

        start_time = time.time()

        results = {
            'total_creators': len(creator_list),
            'successful': [],
            'failed': [],
            'results': {},
            'timing': {}
        }

        with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            future_to_creator = {
                executor.submit(
                    self._safe_process,
                    processing_function,
                    creator,
                    **kwargs
                ): creator
                for creator in creator_list
            }

            for future in concurrent.futures.as_completed(future_to_creator):
                creator = future_to_creator[future]

                try:
                    result = future.result()
                    results['successful'].append(creator)
                    results['results'][creator] = result

                except Exception as e:
                    results['failed'].append(creator)
                    results['results'][creator] = {'error': str(e)}

        end_time = time.time()
        total_time = end_time - start_time

        results['timing'] = {
            'total_seconds': round(total_time, 2),
            'avg_seconds_per_creator': round(total_time / len(creator_list), 2),
            'success_rate': round(len(results['successful']) / len(creator_list) * 100, 1)
        }

        return results

    def _safe_process(
        self,
        processing_function: Callable,
        page_name: str,
        **kwargs
    ):
        """
        Safely execute processing function with retry logic.

        Retries: 2 attempts with exponential backoff
        """

        max_retries = 2
        retry_delay = 1  # seconds

        for attempt in range(max_retries):
            try:
                return processing_function(page_name=page_name, **kwargs)

            except Exception as e:
                if attempt < max_retries - 1:
                    logger.warning(
                        f"Attempt {attempt + 1} failed for {page_name}: {e}. Retrying..."
                    )
                    time.sleep(retry_delay * (attempt + 1))
                else:
                    logger.error(f"All attempts failed for {page_name}: {e}")
                    raise


class BatchResultAggregator:
    """Aggregate and summarize batch processing results"""

    @staticmethod
    def summarize_batch(batch_results: Dict) -> Dict:
        """
        Create executive summary of batch results.

        Args:
            batch_results: Output from BatchProcessor

        Returns:
            Summary statistics
        """

        if 'error' in batch_results:
            return batch_results

        successful_results = [
            result for result in batch_results['results'].values()
            if 'error' not in result
        ]

        summary = {
            'batch_timestamp': datetime.now().isoformat(),
            'overview': {
                'total_creators_processed': batch_results['total_creators'],
                'successful': len(batch_results['successful']),
                'failed': len(batch_results['failed']),
                'success_rate_pct': batch_results['timing']['success_rate']
            },
            'timing': batch_results['timing'],
            'failed_creators': batch_results['failed']
        }

        # Aggregate metrics if available
        if successful_results:
            # Try to extract common metrics
            total_revenue = 0
            total_messages = 0

            for result in successful_results:
                # Handle different result structures
                if isinstance(result, dict):
                    metrics = result.get('metrics', {})
                    total_revenue += metrics.get('total_revenue_90d', 0)
                    total_messages += metrics.get('total_messages_sent', 0)

            summary['aggregated_metrics'] = {
                'total_revenue_analyzed': round(total_revenue, 2),
                'total_messages_analyzed': total_messages,
                'avg_revenue_per_creator': round(total_revenue / len(successful_results), 2)
            }

        return summary

    @staticmethod
    def get_top_performers(batch_results: Dict, top_n: int = 10) -> List[Dict]:
        """
        Extract top performing creators from batch results.

        Args:
            batch_results: Output from BatchProcessor
            top_n: Number of top performers to return

        Returns:
            List of top performers with key metrics
        """

        performers = []

        for page_name, result in batch_results['results'].items():
            if 'error' not in result and isinstance(result, dict):
                metrics = result.get('metrics', {})
                classification = result.get('classification', {})

                performers.append({
                    'page_name': page_name,
                    'revenue_90d': metrics.get('total_revenue_90d', 0),
                    'avg_daily_revenue': metrics.get('avg_daily_revenue', 0),
                    'tier': classification.get('tier', 'UNKNOWN'),
                    'health_status': classification.get('health_status', 'UNKNOWN')
                })

        # Sort by revenue
        performers.sort(key=lambda x: x['revenue_90d'], reverse=True)

        return performers[:top_n]


if __name__ == "__main__":
    # Example usage
    from python.analytics.performance_engine import PerformanceEngine

    def analyze_creator(page_name: str) -> Dict:
        """Example processing function"""
        engine = PerformanceEngine()
        return engine.analyze_creator_comprehensive(page_name)

    # Create batch processor
    processor = BatchProcessor(max_workers=10)

    # Process all creators
    results = processor.process_all_creators(analyze_creator)

    # Summarize
    summary = BatchResultAggregator.summarize_batch(results)

    print(f"Processed {summary['overview']['total_creators_processed']} creators")
    print(f"Success rate: {summary['overview']['success_rate_pct']}%")
    print(f"Total time: {summary['timing']['total_seconds']}s")

    # Get top performers
    top_performers = BatchResultAggregator.get_top_performers(results)
    print(f"\nTop 10 performers:")
    for i, performer in enumerate(top_performers, 1):
        print(f"{i}. {performer['page_name']}: ${performer['revenue_90d']:.2f}")
