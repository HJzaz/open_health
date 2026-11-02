//! Descriptive comparisons of recorded nights, shared by phone and desktop.
//! Missing days stay missing; longest time-in-bed record wins per wake date.
use serde_json::{json, Value};
use std::collections::BTreeMap;

const METRICS: [(&str, &str, &str); 5] = [
    ("hrv_ms", "Nightly HRV", "ms"),
    ("rhr", "Nightly minimum heart rate", "bpm"),
    ("skin_temp", "Skin temperature", "°C"),
    ("spo2_mean", "Blood oxygen", "%"),
    ("in_bed_h", "Time in bed", "h"),
];
fn date_day(s: &str) -> Option<i64> {
    if s.len() != 10 || s.as_bytes()[4] != b'-' || s.as_bytes()[7] != b'-' || !s.bytes().enumerate().all(|(i,b)| i==4 || i==7 || b.is_ascii_digit()) { return None; }
    let y = s[0..4].parse::<i64>().ok()?;
    let m = s[5..7].parse::<u32>().ok()?;
    let d = s[8..10].parse::<u32>().ok()?;
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) { return None; }
    let day = crate::days_from_civil(y,m,d);
    (crate::civil(day)==(y,m,d)).then_some(day)
}
fn label(day: i64) -> String {
    let (y,m,d) = crate::civil(day);
    format!("{y:04}-{m:02}-{d:02}")
}
fn reading(n: &Value, field: &str) -> Option<f64> {
    n[field].as_f64().filter(|v| v.is_finite() && *v > 0.0)
}
fn average(values: &[f64]) -> Option<f64> {
    (!values.is_empty()).then(|| values.iter().map(|v| v / values.len() as f64).sum::<f64>())
}

fn median(mut values: Vec<f64>) -> f64 {
    values.sort_by(f64::total_cmp);
    let middle = values.len()/2;
    if values.len()%2 == 0 { (values[middle-1]+values[middle])/2.0 } else { values[middle] }
}

// Small personal-baseline model. These are engineering thresholds for unusual
// observations, not clinically validated disease thresholds or probabilities.
fn baseline_model(days: &BTreeMap<i64, &Value>, today: i64) -> Value {
    let mut observations = Vec::new();
    let mut largest_baseline = 0;
    if let Some((&day, night)) = days.iter().next_back().filter(|(day,_)| today - **day <= 1) {
        for (field,title,unit,floor) in [("rhr","Nightly minimum heart rate","bpm",2.0),
            ("hrv_ms","Nightly HRV","ms",5.0),("skin_temp","Skin temperature","°C",0.1)] {
            let Some(value) = reading(night,field) else { continue };
            let prior: Vec<f64> = days.range((day-28)..day).filter_map(|(_,n)| reading(n,field)).collect();
            largest_baseline = largest_baseline.max(prior.len());
            if prior.len() < 14 { continue; }
            let center = median(prior.clone());
            let deviation = median(prior.iter().map(|v| (v-center).abs()).collect());
            let scale = (1.4826*deviation).max(floor);
            let score = (value-center)/scale;
            if score.abs() >= 3.5 {
                observations.push(json!({"id":field,"title":title,"unit":unit,"date":label(day),
                    "value":value,"baseline":center,"baseline_nights":prior.len(),
                    "message":format!("{title} was {value:.1} {unit}, {} your usual median of {center:.1} {unit} across {} earlier nights. Review the recording and note recent changes in your routine. This observation does not identify a cause.",if score>0.0 {"above"} else {"below"},prior.len())}));
            }
        }
    }
    json!({"baseline_nights":largest_baseline,"observations":observations,
        "message":if days.iter().next_back().map(|(&d,_)| today-d>1).unwrap_or(true) {
            "No recent overnight readings to assess. Sync your ring; older history is not a current health assessment.".to_string()
        } else if largest_baseline < 14 { format!("Learning your baseline: {largest_baseline}/14 earlier nights available. Each measurement needs 14 readings in the preceding 28 days.") }
        else if observations.is_empty() { "No unusual changes flagged among the eligible recent readings. Missing measurements are not assessed; this is not an all-clear about your health.".into() }
        else { "Changes from your own baseline are worth reviewing; ring readings cannot determine whether you have a health condition.".into() },
        "method":"Local statistical baseline model, not a generative AI or medical risk model. Uses the previous 28 calendar days, at least 14 prior readings per measurement, median and median absolute deviation (MAD). Flags magnitude ≥3.5 robust deviations; minimum scales: 2 bpm, 5 ms, 0.1 °C. These thresholds are not clinically validated. No disease predictions or background alerts."})
}

// Descriptive overnight HR/HRV pattern, not Oura's proprietary daytime stress
// algorithm. Pair baseline readings from the same nights and never score gaps.
fn overnight_stress(days: &BTreeMap<i64, &Value>, today: i64) -> Value {
    let mut result = json!({
        "status":"unavailable", "level":null, "label":"No overnight data",
        "date":null, "baseline_nights":0, "rhr":null, "hrv":null,
        "message":"Wear your ring overnight, then sync to start this estimate.",
        "method":"Experimental overnight physiological strain estimate, not a measurement of mental stress or a live daytime stress score. Compares nightly minimum heart rate and average HRV with paired readings from at least 14 earlier main nights in the previous 28 calendar days. Each baseline uses its median and 1.4826 × MAD, with minimum scales of 2 bpm and 5 ms. Higher strain requires HR ≥1.5 scales above baseline AND HRV ≥1.5 scales below; lower strain requires the reverse. Both within 1.5 scales is the usual range; other patterns are mixed. These engineering thresholds are not clinically validated. Fitness, sleep, illness, medicines and recording quality can affect readings; this estimate cannot identify a cause or rule out a health problem. Calculated from saved data without extra ring sampling."
    });
    let Some((&day, night)) = days.iter().next_back() else { return result };
    result["date"] = json!(label(day));
    if today-day > 1 {
        result["status"] = json!("stale");
        result["label"] = json!("Sync a recent night");
        result["message"] = json!("The latest overnight record is older than yesterday. Sync new data; no current level is assigned.");
        return result;
    }
    let pairs: Vec<(f64,f64)> = days.range((day-28)..day)
        .filter_map(|(_,n)| reading(n,"rhr").zip(reading(n,"hrv_ms"))).collect();
    result["baseline_nights"] = json!(pairs.len());
    let Some((hr,hrv)) = reading(night,"rhr").zip(reading(night,"hrv_ms")) else {
        result["label"] = json!("Missing readings");
        result["message"] = json!("This night needs both heart rate and HRV. Missing values are not treated as low stress.");
        return result;
    };
    if pairs.len() < 14 {
        result["status"] = json!("learning");
        result["label"] = json!("Learning your baseline");
        result["message"] = json!(format!("{}/14 earlier nights with both heart rate and HRV in the preceding 28 days. Keep wearing your ring overnight and sync; no stress level is assigned yet.",pairs.len()));
        return result;
    }
    let hr_base = median(pairs.iter().map(|p|p.0).collect());
    let hrv_base = median(pairs.iter().map(|p|p.1).collect());
    let hr_scale = (1.4826*median(pairs.iter().map(|p|(p.0-hr_base).abs()).collect())).max(2.0);
    let hrv_scale = (1.4826*median(pairs.iter().map(|p|(p.1-hrv_base).abs()).collect())).max(5.0);
    let hr_shift = (hr-hr_base)/hr_scale;
    let hrv_shift = (hrv-hrv_base)/hrv_scale;
    let (level,title,message) = if hr_shift >= 1.5 && hrv_shift <= -1.5 {
        ("higher","Higher strain pattern","Heart rate was higher and HRV lower than your own baseline. Consider a gentler day and time to unwind, and note how you feel. These readings do not explain the cause.")
    } else if hr_shift <= -1.5 && hrv_shift >= 1.5 {
        ("lower","Lower strain pattern","Heart rate was lower and HRV higher than your own baseline. This pattern is not a health all-clear and may not match how you feel.")
    } else if hr_shift.abs() < 1.5 && hrv_shift.abs() < 1.5 {
        ("usual","Within your usual range","Heart rate and HRV were close to your own baseline. This does not mean you have no stress or health concerns.")
    } else {
        ("mixed","Mixed signals","Heart rate and HRV do not show a consistent higher or lower strain pattern. Review the readings and how you feel rather than treating this as a stress level.")
    };
    result["status"] = json!("ready");
    result["level"] = json!(level);
    result["label"] = json!(title);
    result["message"] = json!(message);
    result["rhr"] = json!({"value":hr,"baseline":hr_base,"unit":"bpm"});
    result["hrv"] = json!({"value":hrv,"baseline":hrv_base,"unit":"ms"});
    result
}

pub fn build(nights: &[Value], today: &str) -> Value {
    let Some(today_day) = date_day(today) else { return Value::Null };
    let mut days: BTreeMap<i64, &Value> = BTreeMap::new();
    for night in nights {
        let Some(day) = night["wake_ymd"].as_str().and_then(date_day) else { continue };
        if day > today_day || night["clock_source"].as_str()==Some("undated") { continue; }
        let Some(duration) = reading(night,"in_bed_h") else { continue };
        if duration < 3.0 { continue; } // exclude short rest periods from main-night comparisons
        if days.get(&day).map(|old| reading(old,"in_bed_h").unwrap_or(0.0) >= duration).unwrap_or(false) { continue; }
        days.insert(day,night);
    }
    let latest = days.range(..=today_day).next_back();
    let mut daily = Vec::new();
    if let Some((&day, night)) = latest.filter(|(day,_)| today_day - **day <= 1) {
        for (field,title,unit) in METRICS {
            let Some(value)=reading(night,field) else { continue };
            let prior: Vec<f64> = days.range((day-7)..day).filter_map(|(_,n)| reading(n,field)).collect();
            let baseline = if prior.len()>=3 { average(&prior) } else { None };
            daily.push(json!({"id":field,"title":title,"unit":unit,"date":label(day),
                "value":value,"baseline":baseline,"baseline_nights":prior.len(),
                "delta":baseline.map(|b|value-b),
                "message": if let Some(b)=baseline {
                    format!("{value:.1} {unit}, compared with {b:.1} {unit} across {} earlier nights in the previous 7 days.",prior.len())
                } else {
                    format!("Recorded {value:.1} {unit}. At least 3 earlier nights in the previous 7 days are needed for a comparison.")
                }}));
        }
    }
    let rows: Vec<Value> = METRICS.iter().map(|(field,title,unit)| {
        let current: Vec<(i64,f64)> = days.range((today_day-6)..=today_day)
            .filter_map(|(&d,n)|reading(n,field).map(|v|(d,v))).collect();
        let previous: Vec<f64> = days.range((today_day-13)..=(today_day-7))
            .filter_map(|(_,n)|reading(n,field)).collect();
        let current_values: Vec<f64> = current.iter().map(|(_,v)|*v).collect();
        let a=average(&current_values); let b=average(&previous);
        let comparable=current.len()>=3 && previous.len()>=3;
        json!({"id":field,"title":title,"unit":unit,"current":a,"previous":b,
            "current_nights":current.len(),"previous_nights":previous.len(),
            "comparable":comparable,"delta":if comparable { a.zip(b).map(|(a,b)|a-b) } else { None },
            "points":current.iter().map(|(d,v)|json!({"date":label(*d),"value":v})).collect::<Vec<_>>()})
    }).collect();
    let local_model = baseline_model(&days, today_day);
    json!({"overnight_stress":overnight_stress(&days,today_day),"local_model":local_model,"as_of":today,"latest_night":latest.map(|(&d,_)|label(d)),"daily":daily,
        "message":if days.is_empty() {"Wear your ring overnight, then sync to start your insights."}
                  else if daily.is_empty() {"No recent overnight readings. Sync your ring to refresh these insights."}
                  else {"Comparisons describe your own recorded data; they do not explain a cause or provide a diagnosis."},
        "weekly":{"current_start":label(today_day-6),"current_end":today,
                  "previous_start":label(today_day-13),"previous_end":label(today_day-7),"metrics":rows},
        "method":"One main night of at least 3 hours in bed per wake date. Calendar windows include missing days; averages use recorded nights only. A comparison needs at least 3 readings in each relevant window."})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn night(day: &str,h:f64,hrv:f64)->Value {json!({"wake_ymd":day,"in_bed_h":h,"hrv_ms":hrv,"rhr":60.0})}
    #[test] fn missing_nights_are_not_zeroes() {
        let x=build(&[night("2026-10-31",8.0,40.0)],"2026-10-31");
        assert_eq!(x["weekly"]["metrics"][0]["current"],40.0);
        assert_eq!(x["weekly"]["metrics"][0]["current_nights"],1);
        assert!(x["weekly"]["metrics"][0]["delta"].is_null());
    }
    #[test] fn longest_main_night_wins_and_naps_do_not_count() {
        let x=build(&[night("2026-10-31",8.0,40.0),night("2026-10-31",4.0,99.0),night("2026-10-30",1.0,100.0)],"2026-10-31");
        assert_eq!(x["weekly"]["metrics"][0]["current"],40.0);
        assert_eq!(x["weekly"]["metrics"][0]["current_nights"],1);
    }
    #[test] fn weekly_calendar_boundary_and_counts() {
        let nights=vec![night("2026-10-25",8.0,40.0),night("2026-10-26",8.0,50.0),night("2026-10-31",8.0,60.0),
            night("2026-10-18",8.0,20.0),night("2026-10-19",8.0,30.0),night("2026-10-24",8.0,40.0),night("2026-10-17",8.0,1000.0)];
        let x=build(&nights,"2026-10-31"); let m=&x["weekly"]["metrics"][0];
        assert_eq!(m["current"],50.0);assert_eq!(m["previous"],30.0);assert_eq!(m["delta"],20.0);
        assert_eq!(x["daily"][0]["baseline_nights"],3);
    }
    #[test] fn future_undated_and_invalid_dates_are_excluded() {
        assert!(date_day("ééééé").is_none());
        let mut undated=night("2026-10-31",8.0,50.0);undated["clock_source"]=json!("undated");
        let x=build(&[undated,night("2026-11-01",8.0,30.0),night("2026-02-30",8.0,40.0)],"2026-10-31");
        assert!(x["latest_night"].is_null());assert_eq!(x["daily"].as_array().unwrap().len(),0);
    }
    #[test] fn stale_records_do_not_become_today_insights() {
        let x=build(&[night("2026-10-20",8.0,30.0)],"2026-10-31");
        assert!(x["daily"].as_array().unwrap().is_empty());assert_eq!(x["latest_night"],"2026-10-20");
    }
    #[test] fn model_requires_history_and_excludes_current_night_from_baseline() {
        let mut nights: Vec<Value> = (1..=14).map(|d| night(&format!("2026-10-{d:02}"),8.0,30.0)).collect();
        let current=night("2026-10-15",8.0,70.0);
        let early=build(&[current.clone()],"2026-10-15");
        assert_eq!(early["local_model"]["baseline_nights"],0);
        assert!(early["local_model"]["observations"].as_array().unwrap().is_empty());
        nights.push(current);
        let result=build(&nights,"2026-10-15");
        let flags=result["local_model"]["observations"].as_array().unwrap();
        assert_eq!(flags.len(),1);assert_eq!(flags[0]["baseline"],30.0);
        assert_eq!(flags[0]["baseline_nights"],14);
        assert!(build(&nights,"2026-10-20")["local_model"]["observations"].as_array().unwrap().is_empty());
    }
    #[test] fn model_does_not_treat_missing_values_or_duplicate_nights_as_history() {
        let repeated=vec![night("2026-10-14",8.0,30.0);20];
        let mut rows=repeated;rows.push(night("2026-10-15",8.0,70.0));
        let result=build(&rows,"2026-10-15");
        assert_eq!(result["local_model"]["baseline_nights"],1);
        assert!(result["local_model"]["observations"].as_array().unwrap().is_empty());
    }
    #[test] fn zero_and_missing_values_are_not_averaged() {
        let x=build(&[night("2026-10-31",8.0,0.0)],"2026-10-31");
        assert!(x["weekly"]["metrics"][0]["current"].is_null());
        assert_eq!(x["weekly"]["metrics"][0]["current_nights"],0);
    }
    fn stress_history() -> Vec<Value> {
        (1..=14).map(|d| night(&format!("2026-10-{d:02}"),8.0,40.0)).collect()
    }
    #[test] fn stress_requires_paired_prior_history_and_does_not_score_missing_data() {
        let mut rows=stress_history();
        assert_eq!(build(&rows,"2026-10-14")["overnight_stress"]["status"],"learning");
        rows.push(night("2026-10-15",8.0,0.0));
        let missing=build(&rows,"2026-10-15");
        assert_eq!(missing["overnight_stress"]["status"],"unavailable");
        assert!(missing["overnight_stress"]["level"].is_null());
        rows[14]=night("2026-10-15",8.0,40.0);
        rows[0]["rhr"]=Value::Null;
        let unpaired=build(&rows,"2026-10-15");
        assert_eq!(unpaired["overnight_stress"]["baseline_nights"],13);
        assert_eq!(unpaired["overnight_stress"]["status"],"learning");
        assert!(unpaired["overnight_stress"]["level"].is_null());
    }
    #[test] fn stress_patterns_require_agreement_and_preserve_baseline() {
        for (hr,hrv,level) in [(63.0,32.5,"higher"),(57.0,47.5,"lower"),
            (60.0,40.0,"usual"),(65.0,40.0,"mixed"),(65.0,55.0,"mixed")] {
            let mut rows=stress_history();
            let mut current=night("2026-10-15",8.0,hrv);current["rhr"]=json!(hr);
            rows.push(current);
            let x=build(&rows,"2026-10-15");let s=&x["overnight_stress"];
            assert_eq!(s["level"],level);assert_eq!(s["status"],"ready");
            assert_eq!(s["baseline_nights"],14);
            assert_eq!(s["rhr"]["baseline"],60.0);assert_eq!(s["hrv"]["baseline"],40.0);
        }
    }
    #[test] fn stress_does_not_reuse_stale_levels_or_count_duplicates_old_or_future_nights() {
        let mut rows=stress_history();
        rows.extend(vec![night("2026-10-14",4.0,40.0);10]);
        rows.push(night("2026-09-16",8.0,40.0)); // 29 days before current
        rows.push(night("2026-10-16",8.0,5.0)); // future
        rows.push(night("2026-10-15",8.0,40.0));
        let x=build(&rows,"2026-10-15");
        assert_eq!(x["overnight_stress"]["baseline_nights"],14);
        assert_eq!(x["overnight_stress"]["date"],"2026-10-15");
        let stale=build(&rows,"2026-10-20");
        assert_eq!(stale["overnight_stress"]["status"],"stale");
        assert!(stale["overnight_stress"]["level"].is_null());
        assert!(stale["overnight_stress"]["rhr"].is_null());
        assert!(build(&[],"2026-10-15")["overnight_stress"]["level"].is_null());
    }
}
