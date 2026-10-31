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
    json!({"as_of":today,"latest_night":latest.map(|(&d,_)|label(d)),"daily":daily,
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
    #[test] fn zero_and_missing_values_are_not_averaged() {
        let x=build(&[night("2026-10-31",8.0,0.0)],"2026-10-31");
        assert!(x["weekly"]["metrics"][0]["current"].is_null());
        assert_eq!(x["weekly"]["metrics"][0]["current_nights"],0);
    }
}
