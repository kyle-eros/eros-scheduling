# How to Test the OnlyFans Orchestrator Agent in Claude Code

## Quick Test Instructions

### 1. Simple Test (Single Page)

In your Claude Code session, type:

```
Run the OnlyFans orchestrator for page "jadebri" for week starting 2024-11-04 in optimize mode
```

Expected: The orchestrator should run through all 4 sub-agents and return results.

### 2. Multiple Pages Test

```
I need to generate OnlyFans schedules for these creators: jadebri, miarodriguez, gracebennett
Start date should be Monday 2024-11-04
Use optimize mode and auto-export to Sheets
```

### 3. Test with Validation Gate

```
Generate schedule for page "testpage_red" (which should have RED saturation)
Week start: 2024-11-04
Mode: safe
Verify that export is skipped due to RED saturation
```

## Understanding the Orchestrator

The orchestrator is now a **Claude Code AI agent prompt**, not Python code. It works by:

1. **Reading the prompt** from `/agents/onlyfans-orchestrator.md`
2. **Following instructions** to invoke each sub-agent in sequence
3. **Passing data** between agents using the specified format
4. **Applying validation** gates before export
5. **Returning JSON** with comprehensive results

## How Claude Code Will Execute It

When you ask Claude to run the orchestrator, it will:

### Step 1: Load the Orchestrator Prompt
```
Read: /Users/kylemerriman/Desktop/eros-scheduling-system/agents/onlyfans-orchestrator.md
```

### Step 2: Execute Performance Analyzer
```
Read: /Users/kylemerriman/Desktop/eros-scheduling-system/agents/performance-analyzer.md
Run the SQL queries specified in that agent against BigQuery
Store the results as performance_data
```

### Step 3: Calculate Caption Target
```
Use the formula from orchestrator:
- Extract size_tier and risk_level from performance_data
- Calculate: base_count * saturation_multiplier
- Example: LARGE account (100) * MODERATE risk (0.85) = 85 captions
```

### Step 4: Execute Caption Selector
```
Read: /Users/kylemerriman/Desktop/eros-scheduling-system/agents/caption-selector.md
Run Thompson Sampling SQL with num_captions_needed = 85
Store selected captions as caption_data
```

### Step 5: Execute Schedule Builder
```
Read: /Users/kylemerriman/Desktop/eros-scheduling-system/agents/schedule-builder.md
Build schedule using performance_data + caption_data
Generate schedule_id
Store as schedule_data
```

### Step 6: Apply Validation Gate
```
Check: schedule_data.validation.ok == true?
Check: schedule_data.metadata.saturation_zone != "RED"?
If both true AND auto_export == true: Proceed to export
Otherwise: Skip export with reason
```

### Step 7: Execute Sheets Exporter (if validated)
```
Read: /Users/kylemerriman/Desktop/eros-scheduling-system/agents/sheets-exporter.md
Export schedule to Google Sheets
Return export status
```

### Step 8: Return Results
```json
{
  "orchestration_summary": {
    "status": "completed",
    "total_pages": 1,
    "successful": 1,
    "exported": 1
  },
  "page_results": {
    "jadebri": {
      "status": "success",
      "performance": {...},
      "caption_selection": {...},
      "schedule": {...},
      "export": {"status": "exported"}
    }
  }
}
```

## Expected Output Structure

### Successful Run
```json
{
  "orchestration_summary": {
    "status": "completed",
    "total_pages": 3,
    "successful": 3,
    "failed": 0,
    "exported": 2,
    "skipped_exports": 1,
    "execution_time_seconds": 45.2,
    "saturation_breakdown": {
      "GREEN": 1,
      "YELLOW": 1,
      "RED": 1
    }
  },
  "page_results": {
    "jadebri": {
      "status": "success",
      "performance": {
        "account_classification": {"size_tier": "LARGE"},
        "saturation_analysis": {"risk_level": "MODERATE"}
      },
      "caption_selection": {
        "target_count": 85,
        "selected_count": 85
      },
      "schedule": {
        "schedule_id": "SCH_2024W45_JADEBRI_ABC123",
        "saturation_zone": "YELLOW"
      },
      "export": {
        "status": "exported"
      }
    }
  }
}
```

### With Validation Gate Skip
```json
{
  "page_results": {
    "miarodriguez": {
      "status": "partial_success",
      "schedule": {
        "saturation_zone": "RED"
      },
      "export": {
        "status": "skipped",
        "reason": "RED saturation zone"
      }
    }
  }
}
```

## Troubleshooting

### If the orchestrator doesn't run:
1. Check that all 4 sub-agent .md files exist in `/agents/`
2. Verify BigQuery tables are set up (caption_bank, mass_messages, etc.)
3. Ensure you have BigQuery access configured

### If agents fail:
- Performance Analyzer: Check BigQuery connection and table access
- Caption Selector: Verify caption_bank table has data
- Schedule Builder: Check that captions were selected properly
- Sheets Exporter: Verify Google Sheets API access

### Common Issues:
1. **"Agent file not found"** - The .md files must be in the correct location
2. **"No captions available"** - caption_bank table might be empty
3. **"Export skipped"** - Check validation gate (ok=true, saturation!=RED)
4. **"BigQuery timeout"** - Queries may need optimization or tables need indexes

## Key Differences from Python Version

| Old (Python) | New (Claude Code Agent) |
|--------------|------------------------|
| Import Python modules | Read .md agent prompts |
| Execute Python functions | Follow agent instructions |
| ThreadPoolExecutor | Claude handles parallel execution |
| asyncio.gather() | Agent orchestration logic |
| Python try/except | Agent error handling instructions |

## Testing Parallel Execution

To test parallel processing:

```
Generate schedules for 6 pages: jadebri, miarodriguez, gracebennett, emmarose, sofiastars, lunanight
Week: 2024-11-04
Mode: optimize
Enable parallel processing
```

The orchestrator should:
1. Run Performance Analyzer sequentially for all 6
2. Run Caption Selector in parallel for all 6
3. Run Schedule Builder in parallel for all 6
4. Run Sheets Exporter in parallel for eligible pages

## Success Criteria

✅ The orchestrator successfully:
1. Reads and interprets the agent prompt
2. Invokes all 4 sub-agents in correct sequence
3. Passes data between agents correctly
4. Applies validation gates (skips RED saturation)
5. Handles errors with retries
6. Returns comprehensive JSON results
7. Processes multiple pages when requested
8. Respects the schedule_id throughout the flow

## Next Steps

1. **Test with real data**: Use actual page names from your BigQuery tables
2. **Monitor performance**: Check execution times for optimization opportunities
3. **Validate outputs**: Ensure schedules meet business requirements
4. **Add custom logic**: Modify the orchestrator.md for specific needs

The orchestrator is now a proper Claude Code AI agent that can be invoked directly in your Claude Code session!