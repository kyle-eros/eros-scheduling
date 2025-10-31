# Claude Code AI Agents

This directory contains the 5 Claude Code AI agent prompts that power the EROS Scheduling System.

## The Agents

### 1. **onlyfans-orchestrator.md** (Master Controller)
- Coordinates all 4 sub-agents
- Calculates optimal caption counts
- Applies validation gates
- Handles errors and retries
- Processes multiple pages in parallel

**When to use:** This is the main agent you invoke. It calls all the others automatically.

### 2. **performance-analyzer.md**
- Analyzes creator performance metrics
- Classifies account size (SMALL, MEDIUM, LARGE, XL)
- Calculates saturation scores and risk levels
- Provides optimization recommendations

**Called by:** Orchestrator (automatically)

### 3. **caption-selector.md**
- Selects optimal captions using Thompson Sampling
- Uses Wilson Score for confidence intervals
- Balances exploration vs exploitation
- Returns PPV and Bump caption pools

**Called by:** Orchestrator (automatically)

### 4. **schedule-builder.md**
- Builds optimized weekly schedules
- Respects daily message limits by account size
- Responds to saturation zones (GREEN/YELLOW/RED)
- Generates unique schedule_id
- Persists to BigQuery

**Called by:** Orchestrator (automatically)

### 5. **sheets-exporter.md**
- Exports validated schedules to Google Sheets
- Read-only from BigQuery view
- Only exports if validation passes and not RED saturation
- Logs export status

**Called by:** Orchestrator (automatically, after validation)

## How They Work

These are **not Python scripts** - they are Claude Code AI agent prompts.

When you invoke the orchestrator:
1. Claude reads the orchestrator.md prompt
2. Follows the instructions to call each sub-agent
3. Each sub-agent executes its SQL queries and logic
4. Data flows between agents via JSON
5. Results are validated at each step
6. Final output is comprehensive JSON

## Usage

You don't call these agents individually (except for debugging). Just call the orchestrator:

```
Run the OnlyFans orchestrator for page "jadebri"
for week starting 2024-11-04 in optimize mode with auto-export
```

The orchestrator handles everything else automatically.

## File Structure

- **443 lines** - onlyfans-orchestrator.md (master)
- **42,571 bytes** - performance-analyzer.md
- **38,210 bytes** - caption-selector.md
- **34,462 bytes** - schedule-builder.md
- **26,021 bytes** - sheets-exporter.md

## Key Concepts

### Caption Target Formula
```
base_count = {NEW: 40, SMALL: 60, MEDIUM: 80, LARGE: 100, XL: 140}
saturation_multiplier = {LOW: 1.00, MODERATE: 0.85, HIGH: 0.70, CRITICAL: 0.55}
final_count = MAX(30, base_count * saturation_multiplier)
```

### Validation Gates
- ✅ validation.ok == true
- ✅ saturation_zone != "RED"
- ✅ auto_export == true

### Data Flow
```
Performance Analyzer → Metrics
  ↓
Caption Target Calculation → Count
  ↓
Caption Selector → Captions
  ↓
Schedule Builder → Schedule
  ↓
Validation Gate → Pass/Skip
  ↓
Sheets Exporter → Export (if passed)
```

## Debugging Individual Agents

If you need to test a single agent:

```
# Test performance analyzer
Run the performance analyzer agent for page "jadebri"
with 90 day lookback and include saturation analysis

# Test caption selector (requires count)
Run the caption selector agent for page "jadebri"
with 85 captions needed
```

## Architecture

This is a **prompt-based AI agent system**, not traditional code. The .md files contain:
- Agent identity and role
- Workflow instructions
- SQL queries to execute
- Data validation rules
- Output format specifications

Claude Code interprets these prompts and executes the workflow autonomously.

## Version

- Type: Claude Code AI Agents
- Architecture: Multi-Agent Orchestration
- Version: 2.0 (Native Claude Code)
- Last Updated: October 31, 2024