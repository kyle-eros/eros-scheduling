"""
Test script for Issue 3: Race Condition in Caption Locking
Tests that the MERGE-based atomic locking prevents duplicate caption assignments
when multiple concurrent requests attempt to lock the same caption.
"""

import concurrent.futures
import time
from google.cloud import bigquery
from datetime import datetime, timedelta


class CaptionLockingRaceConditionTest:
    """Test suite for atomic caption locking mechanism"""

    def __init__(self, project_id='of-scheduler-proj'):
        self.client = bigquery.Client(project=project_id)
        self.test_caption_id = 99999  # Test caption ID
        self.test_page_name = 'test_creator_race'

    def setup_test_data(self):
        """Create test caption in caption_bank"""
        print("Setting up test data...")

        # Insert test caption
        query = f"""
        INSERT INTO `of-scheduler-proj.eros_scheduling_brain.caption_bank` (
            caption_id,
            caption_text,
            price_tier,
            psychological_trigger,
            content_category,
            caption_length,
            emoji_count,
            question_count,
            urgency_score,
            exclusivity_score,
            is_active
        ) VALUES (
            {self.test_caption_id},
            'Test caption for race condition validation',
            'premium',
            'Urgency',
            'B/G',
            45,
            2,
            0,
            0.8,
            0.6,
            TRUE
        )
        ON CONFLICT (caption_id) DO NOTHING;
        """

        try:
            self.client.query(query).result()
            print(f"✓ Test caption {self.test_caption_id} created/exists")
        except Exception as e:
            print(f"Note: {e} (caption may already exist)")

    def cleanup_test_data(self):
        """Remove test assignments"""
        print("\nCleaning up test data...")

        query = f"""
        DELETE FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
        WHERE caption_id = {self.test_caption_id}
            OR page_name = '{self.test_page_name}';
        """

        try:
            result = self.client.query(query).result()
            print(f"✓ Cleanup complete (affected rows: {result.total_rows})")
        except Exception as e:
            print(f"Cleanup warning: {e}")

    def attempt_lock(self, thread_id):
        """
        Attempt to lock the same caption from a thread.
        This simulates concurrent schedule generation requests.
        """
        schedule_id = f'test_schedule_race_{thread_id}_{int(time.time())}'
        scheduled_date = (datetime.now() + timedelta(days=3)).strftime('%Y-%m-%d')

        query = f"""
        CALL `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`(
            '{schedule_id}',
            '{self.test_page_name}',
            [
                STRUCT(
                    {self.test_caption_id} AS caption_id,
                    DATE('{scheduled_date}') AS scheduled_date,
                    14 AS send_hour,
                    'exploit' AS selection_strategy,
                    0.85 AS confidence_score
                )
            ]
        );
        """

        start_time = time.time()

        try:
            result = self.client.query(query).result()
            elapsed = time.time() - start_time
            return {
                'thread_id': thread_id,
                'status': 'SUCCESS',
                'schedule_id': schedule_id,
                'elapsed_ms': int(elapsed * 1000),
                'result': result
            }
        except Exception as e:
            elapsed = time.time() - start_time
            return {
                'thread_id': thread_id,
                'status': 'CONFLICT',
                'error': str(e),
                'elapsed_ms': int(elapsed * 1000)
            }

    def test_concurrent_locking(self, num_threads=10):
        """
        Main test: Execute N concurrent attempts to lock the same caption.
        Expected: Exactly 1 SUCCESS, N-1 CONFLICTS
        """
        print(f"\n{'='*70}")
        print(f"Running Race Condition Test with {num_threads} concurrent threads")
        print(f"{'='*70}\n")

        # Setup
        self.cleanup_test_data()
        self.setup_test_data()

        # Execute concurrent attempts
        print(f"Launching {num_threads} concurrent lock attempts...")
        start_time = time.time()

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_threads) as executor:
            futures = [executor.submit(self.attempt_lock, i) for i in range(num_threads)]
            results = [f.result() for f in concurrent.futures.as_completed(futures)]

        total_elapsed = time.time() - start_time

        # Analyze results
        successes = [r for r in results if r['status'] == 'SUCCESS']
        conflicts = [r for r in results if r['status'] == 'CONFLICT']

        print(f"\n{'='*70}")
        print("TEST RESULTS")
        print(f"{'='*70}")
        print(f"Total execution time: {total_elapsed:.2f}s")
        print(f"Successes: {len(successes)}")
        print(f"Conflicts: {len(conflicts)}")

        # Print details
        if successes:
            print(f"\n✓ Successful Lock:")
            for s in successes:
                print(f"  - Thread {s['thread_id']}: {s['schedule_id']} ({s['elapsed_ms']}ms)")

        if conflicts:
            print(f"\n✗ Conflicted Attempts:")
            for c in conflicts[:5]:  # Show first 5
                error_snippet = c['error'][:100] + "..." if len(c['error']) > 100 else c['error']
                print(f"  - Thread {c['thread_id']}: {error_snippet} ({c['elapsed_ms']}ms)")
            if len(conflicts) > 5:
                print(f"  ... and {len(conflicts) - 5} more conflicts")

        # Validation
        print(f"\n{'='*70}")
        print("VALIDATION")
        print(f"{'='*70}")

        passed = True

        # Check 1: Exactly 1 success
        if len(successes) == 1:
            print("✅ PASS: Exactly 1 thread succeeded (atomic locking working)")
        else:
            print(f"❌ FAIL: {len(successes)} threads succeeded (expected 1)")
            print("   Issue: Race condition still exists - MERGE not preventing duplicates")
            passed = False

        # Check 2: N-1 conflicts
        if len(conflicts) == num_threads - 1:
            print(f"✅ PASS: {len(conflicts)} threads detected conflicts (expected {num_threads - 1})")
        else:
            print(f"⚠️  WARNING: {len(conflicts)} conflicts (expected {num_threads - 1})")

        # Check 3: Conflict messages contain "ATOMIC ROLLBACK"
        atomic_rollback_count = sum(1 for c in conflicts if 'ATOMIC ROLLBACK' in c.get('error', ''))
        if atomic_rollback_count == len(conflicts):
            print(f"✅ PASS: All conflicts have 'ATOMIC ROLLBACK' message")
        else:
            print(f"⚠️  WARNING: Only {atomic_rollback_count}/{len(conflicts)} conflicts have rollback message")

        # Check 4: Verify database state
        verify_query = f"""
        SELECT
            caption_id,
            COUNT(*) as assignment_count,
            ARRAY_AGG(schedule_id) as schedules,
            ARRAY_AGG(locked_at) as lock_times
        FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
        WHERE caption_id = {self.test_caption_id}
            AND is_active = TRUE
        GROUP BY caption_id;
        """

        db_result = list(self.client.query(verify_query).result())

        if len(db_result) == 0:
            print("❌ FAIL: No assignments found in database (expected 1)")
            passed = False
        elif len(db_result) == 1 and db_result[0]['assignment_count'] == 1:
            print("✅ PASS: Exactly 1 assignment in database (no duplicates)")
        else:
            print(f"❌ FAIL: {db_result[0]['assignment_count']} assignments found (expected 1)")
            print("   Issue: Duplicate caption assignments exist - CRITICAL RACE CONDITION")
            passed = False

        # Final verdict
        print(f"\n{'='*70}")
        if passed:
            print("✅✅✅ ALL TESTS PASSED - RACE CONDITION FIXED ✅✅✅")
        else:
            print("❌❌❌ TESTS FAILED - RACE CONDITION EXISTS ❌❌❌")
        print(f"{'='*70}\n")

        return passed

    def run_full_test_suite(self):
        """Run comprehensive test suite"""
        try:
            # Test 1: 10 concurrent threads
            print("\n" + "="*70)
            print("TEST 1: 10 Concurrent Threads")
            print("="*70)
            test1_passed = self.test_concurrent_locking(num_threads=10)

            # Cleanup between tests
            self.cleanup_test_data()
            time.sleep(2)

            # Test 2: 50 concurrent threads (stress test)
            print("\n" + "="*70)
            print("TEST 2: 50 Concurrent Threads (Stress Test)")
            print("="*70)
            test2_passed = self.test_concurrent_locking(num_threads=50)

            # Final cleanup
            self.cleanup_test_data()

            # Summary
            print("\n" + "="*70)
            print("FINAL TEST SUITE SUMMARY")
            print("="*70)
            print(f"Test 1 (10 threads):  {'✅ PASSED' if test1_passed else '❌ FAILED'}")
            print(f"Test 2 (50 threads):  {'✅ PASSED' if test2_passed else '❌ FAILED'}")

            if test1_passed and test2_passed:
                print("\n🎉 Issue 3 FIX VALIDATED - Atomic locking prevents all race conditions")
            else:
                print("\n⚠️  Issue 3 FIX INCOMPLETE - Race conditions still detected")

            return test1_passed and test2_passed

        except Exception as e:
            print(f"\n❌ Test suite error: {e}")
            import traceback
            traceback.print_exc()
            return False


if __name__ == '__main__':
    print("""
    ╔══════════════════════════════════════════════════════════════════════╗
    ║  Caption Locking Race Condition Test - Issue 3 Validation           ║
    ║  Tests atomic MERGE operation prevents duplicate caption assignments ║
    ╚══════════════════════════════════════════════════════════════════════╝
    """)

    tester = CaptionLockingRaceConditionTest()
    success = tester.run_full_test_suite()

    exit(0 if success else 1)
