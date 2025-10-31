# Quick Start Guide - EROS Scheduling System

## What This System Does

The EROS Scheduling System is a Claude Code AI agent workflow that automatically generates optimized OnlyFans content schedules. Just paste a prompt into Claude Code and it handles everything.

## Prerequisites (One-Time Setup)

1. **Claude Code CLI** installed
2. **BigQuery access** to project `of-scheduler-proj`
3. **Agent files** in `/agents/` directory (already present)

## How to Use (3 Steps)

### Step 1: Get Your Prompt

Open `QUICK_PROMPTS_CHEATSHEET.txt` and find the page you want to schedule.

### Step 2: Adjust the Date

Change `2024-11-04` to the Monday of the week you want to schedule.

**November 2024 Mondays:**
- 2024-11-04, 2024-11-11, 2024-11-18, 2024-11-25

**December 2024 Mondays:**
- 2024-12-02, 2024-12-09, 2024-12-16, 2024-12-23, 2024-12-30

### Step 3: Paste into Claude Code

Copy the prompt and paste it into your Claude Code session. Press Enter.

## Examples

### Single Page
```
Run the OnlyFans orchestrator for page "jadebri"
for week starting 2024-11-04 in optimize mode with auto-export
```

### Multiple Pages
```
Generate OnlyFans schedules for pages: jadebri, miarodriguez, gracebennett
Week: 2024-11-04, mode: optimize, auto-export: true, parallel: true
```

### All Pages
```
Generate OnlyFans schedules for pages: adriannarodriguez, alexlove, anngrayson, ashlyroux, aspynhayes, calilove, carmenrose, chloewildd, corvettemikayla, del, dianagrace, gracebennett_free, gracebennett_paid, isabellelayla, itskassielee_free, itskassielee_paid, jadebri, jadevalentine, jadewilkinson, kayleighashford, lolarivers, madisonsummers, miafoster, miaharper, missalexa_free, missalexa_paid, neenah, norarhodes, oliviahansley_free, oliviahansley_paid, poutyselena, scarlettgraceee, talia, taylorwild_paid, tessadove, tessatan, tessathomas_paid, myahill. Week: 2024-11-04, mode: optimize, auto-export: true, parallel: true
```

## What Happens Next

Claude will:
1. ✅ Run the orchestrator agent
2. ✅ Call 4 sub-agents (analyzer, selector, builder, exporter)
3. ✅ Generate optimal schedules with validation
4. ✅ Export to Google Sheets (if validated)
5. ✅ Return comprehensive results

Typical execution time: 8-30 seconds per page

## Expected Output

```json
{
  "orchestration_summary": {
    "status": "completed",
    "total_pages": 1,
    "successful": 1,
    "exported": 1,
    "execution_time_seconds": 8.2
  },
  "page_results": {
    "jadebri": {
      "status": "success",
      "schedule": {
        "schedule_id": "SCH_2024W45_JADEBRI_ABC123",
        "total_messages": 42
      },
      "export": {
        "status": "exported"
      }
    }
  }
}
```

## Common Modes

- **optimize** (default): Maximum revenue, respects all constraints
- **safe**: Conservative approach, wider message gaps
- **conservative**: Minimal messaging, lowest saturation risk

## Troubleshooting

**"No captions available"**
→ Check caption_bank table has data for the page

**"Export skipped"**
→ Check if schedule validation failed or saturation is RED

**"Agent file not found"**
→ Ensure all .md files exist in `/agents/` directory

## Next Steps

- See `README.md` for detailed system overview
- See `QUICK_PROMPTS_CHEATSHEET.txt` for all page prompts
- See `docs/OPERATIONAL_RUNBOOK.md` for daily operations
- See `docs/TEST_ORCHESTRATOR.md` for testing guide

## That's It!

The system is designed to be simple: **Copy → Adjust Date → Paste → Done**

No coding, no scripts, no configuration needed. Just natural language prompts.