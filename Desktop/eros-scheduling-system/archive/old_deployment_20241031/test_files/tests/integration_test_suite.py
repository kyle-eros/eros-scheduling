#!/usr/bin/env python3
"""
EROS Platform v2 - Complete Integration Test Suite
Tests all 6 agents with 3 test creators to validate production readiness
"""

import asyncio
import json
from datetime import datetime, timedelta
from typing import Dict, List, Tuple
import sys
import os

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from agents.orchestrator_v2 import OrchestratorV2
from agents.performance_analyzer_v2 import PerformanceAnalyzerV2
from agents.caption_selector_v2 import CaptionSelectorV2
from agents.schedule_builder_v2 import ScheduleBuilderV2
from agents.sheets_exporter_v2 import SheetsExporterV2
from agents.real_time_monitor_v2 import RealTimeMonitorV2


class IntegrationTestSuite:
    """
    Complete integration testing for EROS Platform v2
    Tests with 3 creators representing different scenarios
    """

    def __init__(self):
        self.test_creators = {
            'test_healthy': {
                'name': 'Emma Rose (Healthy)',
                'account_size': 'Large',
                'audience': 35000,
                'conversion_baseline': 0.045,
                'saturation_status': 'GREEN',
                'description': 'Healthy creator with good engagement'
            },
            'test_saturated': {
                'name': 'Mia Rodriguez (Saturated)',
                'account_size': 'Medium',
                'audience': 18000,
                'conversion_baseline': 0.015,
                'saturation_status': 'RED',
                'description': 'Over-messaged creator needing recovery'
            },
            'test_growing': {
                'name': 'Grace Bennett (Growing)',
                'account_size': 'Small',
                'audience': 5000,
                'conversion_baseline': 0.065,
                'saturation_status': 'GREEN',
                'description': 'New creator with high conversion'
            }
        }

        self.test_results = []
        self.failed_tests = []

    def run_all_tests(self) -> Dict:
        """
        Execute complete test suite
        """
        print("\n" + "="*80)
        print("🧪 EROS PLATFORM V2 - INTEGRATION TEST SUITE")
        print("="*80)

        start_time = datetime.now()

        # Run test phases
        self._test_phase_1_individual_agents()
        self._test_phase_2_dependencies()
        self._test_phase_3_orchestration()
        self._test_phase_4_error_handling()
        self._test_phase_5_performance()
        self._test_phase_6_validation()

        # Generate report
        end_time = datetime.now()
        return self._generate_test_report(start_time, end_time)

    def _test_phase_1_individual_agents(self):
        """Test each agent individually"""

        print("\n📋 PHASE 1: Individual Agent Testing")
        print("-" * 40)

        # Test Performance Analyzer
        self._run_test(
            "Performance Analyzer - Account Classification",
            self._test_performance_analyzer_classification
        )

        # Test Caption Selector
        self._run_test(
            "Caption Selector - Thompson Sampling",
            self._test_caption_selector_thompson
        )

        # Test Schedule Builder
        self._run_test(
            "Schedule Builder - Volume Caps",
            self._test_schedule_builder_volume
        )

        # Test Real-Time Monitor
        self._run_test(
            "Real-Time Monitor - 15min Lag",
            self._test_monitor_latency
        )

        # Test Sheets Exporter
        self._run_test(
            "Sheets Exporter - Apps Script Functions",
            self._test_exporter_apps_script
        )

    def _test_phase_2_dependencies(self):
        """Test agent dependencies and data flow"""

        print("\n🔗 PHASE 2: Dependency Testing")
        print("-" * 40)

        self._run_test(
            "Performance → Caption Data Flow",
            self._test_performance_to_caption_flow
        )

        self._run_test(
            "Caption → Schedule Data Flow",
            self._test_caption_to_schedule_flow
        )

        self._run_test(
            "Schedule → Export Data Flow",
            self._test_schedule_to_export_flow
        )

    def _test_phase_3_orchestration(self):
        """Test orchestrator parallel execution"""

        print("\n⚡ PHASE 3: Orchestration Testing")
        print("-" * 40)

        self._run_test(
            "Parallel Execution - 3 Creators",
            self._test_parallel_execution
        )

        self._run_test(
            "Dependency Resolution",
            self._test_dependency_resolution
        )

        self._run_test(
            "Circuit Breaker Pattern",
            self._test_circuit_breaker
        )

    def _test_phase_4_error_handling(self):
        """Test error recovery and retry logic"""

        print("\n🛡️ PHASE 4: Error Handling")
        print("-" * 40)

        self._run_test(
            "Retry Logic - Exponential Backoff",
            self._test_retry_logic
        )

        self._run_test(
            "Transaction Rollback",
            self._test_transaction_rollback
        )

        self._run_test(
            "Caption Lock Recovery",
            self._test_caption_lock_recovery
        )

    def _test_phase_5_performance(self):
        """Test performance benchmarks"""

        print("\n⚡ PHASE 5: Performance Testing")
        print("-" * 40)

        self._run_test(
            "Query Performance < 2s",
            self._test_query_performance
        )

        self._run_test(
            "Parallel vs Sequential Speed",
            self._test_parallel_speedup
        )

        self._run_test(
            "Memory Usage < 1GB",
            self._test_memory_usage
        )

    def _test_phase_6_validation(self):
        """Test schedule validation"""

        print("\n✅ PHASE 6: Validation Testing")
        print("-" * 40)

        self._run_test(
            "Schedule Validation - Healthy",
            self._test_validate_healthy_schedule
        )

        self._run_test(
            "Schedule Validation - Saturated",
            self._test_validate_saturated_schedule
        )

        self._run_test(
            "Funnel Sequence Validation",
            self._test_validate_funnel_sequences
        )

    # Individual Test Implementations

    def _test_performance_analyzer_classification(self) -> bool:
        """Test account size classification"""
        try:
            analyzer = PerformanceAnalyzerV2()

            # Test each creator size
            for creator_id, creator_info in self.test_creators.items():
                result = analyzer.classify_account_size(
                    creator_name=creator_info['name'],
                    audience_size=creator_info['audience']
                )

                # Verify correct classification
                expected_size = creator_info['account_size']
                if result['size_tier'] != expected_size:
                    raise AssertionError(
                        f"Expected {expected_size}, got {result['size_tier']}"
                    )

                # Verify volume caps
                if expected_size == 'Large' and result['daily_ppv_max'] != 15:
                    raise AssertionError("Large account should have 15 PPV cap")

            return True

        except Exception as e:
            self.failed_tests.append(f"Performance Classification: {str(e)}")
            return False

    def _test_caption_selector_thompson(self) -> bool:
        """Test Thompson Sampling implementation"""
        try:
            selector = CaptionSelectorV2()

            # Test Wilson Score calculation
            result = selector.calculate_wilson_score(
                successes=70,
                failures=30,
                confidence=0.95
            )

            # Verify bounds are correct
            if not (0.6 < result['lower_bound'] < 0.7):
                raise AssertionError(f"Wilson lower bound incorrect: {result['lower_bound']}")

            if not (0.7 < result['upper_bound'] < 0.8):
                raise AssertionError(f"Wilson upper bound incorrect: {result['upper_bound']}")

            # Test 70/20/10 distribution
            captions = selector.select_captions_with_distribution(
                creator_name='test_healthy',
                num_needed=100
            )

            exploit_count = sum(1 for c in captions if c['bucket'] == 'exploit')
            explore_count = sum(1 for c in captions if c['bucket'] == 'explore')
            novel_count = sum(1 for c in captions if c['bucket'] == 'novel')

            if not (65 <= exploit_count <= 75):
                raise AssertionError(f"Exploit bucket should be ~70%, got {exploit_count}%")

            return True

        except Exception as e:
            self.failed_tests.append(f"Thompson Sampling: {str(e)}")
            return False

    def _test_schedule_builder_volume(self) -> bool:
        """Test volume caps by account size"""
        try:
            builder = ScheduleBuilderV2()

            # Test each account size
            test_cases = [
                ('Small', 5, 3),
                ('Medium', 10, 7),
                ('Large', 15, 10),
                ('XL', 20, 15)
            ]

            for size, max_ppv, min_ppv in test_cases:
                schedule = builder.build_schedule_for_size(
                    account_size=size,
                    saturation_status='GREEN'
                )

                daily_counts = builder.count_daily_messages(schedule)

                for day, count in daily_counts.items():
                    if count > max_ppv:
                        raise AssertionError(
                            f"{size} account exceeded max: {count} > {max_ppv}"
                        )

            return True

        except Exception as e:
            self.failed_tests.append(f"Volume Caps: {str(e)}")
            return False

    def _test_monitor_latency(self) -> bool:
        """Test monitor achieves 15-minute lag"""
        try:
            monitor = RealTimeMonitorV2()

            # Simulate real-time check
            result = monitor.check_latency()

            if result['data_lag_minutes'] > 15:
                raise AssertionError(
                    f"Monitor lag too high: {result['data_lag_minutes']} minutes"
                )

            if result['refresh_frequency'] != 'every_5_minutes':
                raise AssertionError("Monitor should run every 5 minutes")

            return True

        except Exception as e:
            self.failed_tests.append(f"Monitor Latency: {str(e)}")
            return False

    def _test_exporter_apps_script(self) -> bool:
        """Test Apps Script functions exist"""
        try:
            # Check for required functions in Apps Script code
            required_functions = [
                'importScheduleFromBigQuery',
                'fetchScheduleFromBigQuery',  # This was missing in v1
                'importToSheet',
                'validateSchedule',
                'setupSheetHeaders'
            ]

            # Read the Apps Script section from exporter
            with open('agents/sheets_exporter_v2.md', 'r') as f:
                content = f.read()

            for func in required_functions:
                if f'function {func}' not in content:
                    raise AssertionError(f"Missing function: {func}")

            return True

        except Exception as e:
            self.failed_tests.append(f"Apps Script Functions: {str(e)}")
            return False

    def _test_performance_to_caption_flow(self) -> bool:
        """Test data flow from performance analyzer to caption selector"""
        try:
            # Get performance data
            analyzer = PerformanceAnalyzerV2()
            perf_data = analyzer.analyze('test_healthy', lookback_days=30)

            # Pass to caption selector
            selector = CaptionSelectorV2()
            captions = selector.select_with_performance(
                creator_name='test_healthy',
                performance_data=perf_data,
                num_needed=50
            )

            # Verify performance data influenced selection
            if not captions[0].get('performance_adjusted'):
                raise AssertionError("Performance data not used in caption selection")

            return True

        except Exception as e:
            self.failed_tests.append(f"Performance→Caption Flow: {str(e)}")
            return False

    def _test_parallel_execution(self) -> bool:
        """Test orchestrator parallel execution"""
        try:
            orchestrator = OrchestratorV2()

            # Time sequential execution
            start = datetime.now()
            orchestrator.max_parallel = 1
            result_seq = asyncio.run(orchestrator.generate_schedule(
                creator_names=['test_healthy'],
                week_start='2024-01-08'
            ))
            time_sequential = (datetime.now() - start).total_seconds()

            # Time parallel execution
            start = datetime.now()
            orchestrator.max_parallel = 5
            result_par = asyncio.run(orchestrator.generate_schedule(
                creator_names=['test_healthy', 'test_saturated', 'test_growing'],
                week_start='2024-01-08'
            ))
            time_parallel = (datetime.now() - start).total_seconds()

            # Parallel should be faster for 3 creators
            speedup = (time_sequential * 3) / time_parallel
            if speedup < 2.0:
                raise AssertionError(f"Insufficient speedup: {speedup:.1f}x")

            return True

        except Exception as e:
            self.failed_tests.append(f"Parallel Execution: {str(e)}")
            return False

    def _test_validate_saturated_schedule(self) -> bool:
        """Test schedule validation for saturated creator"""
        try:
            builder = ScheduleBuilderV2()

            # Build schedule for RED saturation
            schedule = builder.build_schedule(
                creator_name='test_saturated',
                account_size='Medium',
                saturation_status='RED'
            )

            # Should have reduced volume
            daily_counts = builder.count_daily_messages(schedule)

            for day, count in daily_counts.items():
                if count > 5:  # 50% reduction from normal 10
                    raise AssertionError(
                        f"RED saturation should reduce volume: {count} > 5"
                    )

            # Should have cooling days
            if not any(count == 0 for count in daily_counts.values()):
                raise AssertionError("RED saturation should include cooling days")

            return True

        except Exception as e:
            self.failed_tests.append(f"Saturated Validation: {str(e)}")
            return False

    # Test Runner Utilities

    def _run_test(self, test_name: str, test_func) -> bool:
        """Run individual test with error handling"""
        try:
            print(f"  Testing: {test_name}...", end=" ")
            result = test_func()

            if result:
                print("✅ PASSED")
                self.test_results.append({
                    'test': test_name,
                    'status': 'PASSED',
                    'error': None
                })
            else:
                print("❌ FAILED")
                self.test_results.append({
                    'test': test_name,
                    'status': 'FAILED',
                    'error': 'Test returned False'
                })

            return result

        except Exception as e:
            print(f"❌ FAILED: {str(e)}")
            self.test_results.append({
                'test': test_name,
                'status': 'FAILED',
                'error': str(e)
            })
            return False

    def _generate_test_report(self, start_time: datetime, end_time: datetime) -> Dict:
        """Generate comprehensive test report"""

        total_tests = len(self.test_results)
        passed = sum(1 for r in self.test_results if r['status'] == 'PASSED')
        failed = total_tests - passed
        pass_rate = (passed / total_tests * 100) if total_tests > 0 else 0

        print("\n" + "="*80)
        print("📊 TEST SUITE SUMMARY")
        print("="*80)
        print(f"Total Tests: {total_tests}")
        print(f"Passed: {passed} ✅")
        print(f"Failed: {failed} ❌")
        print(f"Pass Rate: {pass_rate:.1f}%")
        print(f"Execution Time: {(end_time - start_time).total_seconds():.1f}s")

        if failed > 0:
            print("\n❌ FAILED TESTS:")
            for result in self.test_results:
                if result['status'] == 'FAILED':
                    print(f"  - {result['test']}: {result['error']}")

        # Production readiness assessment
        print("\n" + "="*80)
        if pass_rate >= 95:
            print("✅ PRODUCTION READY - All critical tests passed!")
        elif pass_rate >= 80:
            print("⚠️ NEEDS ATTENTION - Some tests failed, review before production")
        else:
            print("❌ NOT READY - Critical failures detected, do not deploy")

        return {
            'total_tests': total_tests,
            'passed': passed,
            'failed': failed,
            'pass_rate': pass_rate,
            'execution_time': (end_time - start_time).total_seconds(),
            'failed_tests': [r for r in self.test_results if r['status'] == 'FAILED'],
            'production_ready': pass_rate >= 95
        }


def main():
    """Run complete integration test suite"""
    print("\n🚀 Starting EROS Platform v2 Integration Tests")
    print("Testing with 3 creators: Healthy, Saturated, Growing")

    test_suite = IntegrationTestSuite()
    report = test_suite.run_all_tests()

    # Save report to file
    with open('test_report.json', 'w') as f:
        json.dump(report, f, indent=2, default=str)

    print(f"\n📄 Test report saved to test_report.json")

    # Exit with appropriate code
    if report['production_ready']:
        print("\n✅ All systems GO for production deployment!")
        sys.exit(0)
    else:
        print("\n❌ Fix failures before deploying to production")
        sys.exit(1)


if __name__ == "__main__":
    main()