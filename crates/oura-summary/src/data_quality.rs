//! Saved-data diagnostics only: no BLE requests or health classifications.
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use crate::ring_time::RingClock;

const DAY: f64 = 86400.0;

fn battery_report(readings: &[(f64,i64)], now: f64) -> Value {
    // Conflicting readings at one timestamp are unusable, not separate evidence.
    let mut unique: BTreeMap<i64,Option<i64>> = BTreeMap::new();
    for &(at,pct) in readings {
        if !at.is_finite() || at <= 0.0 || at > now || at < now-3.0*DAY || !(0..=100).contains(&pct) { continue; }
        unique.entry(at.floor() as i64).and_modify(|old| { if *old != Some(pct) { *old=None; } }).or_insert(Some(pct));
    }
    let mut segment: Vec<(i64,i64)> = Vec::new();
    for (at,pct) in unique.into_iter().filter_map(|(t,p)|p.map(|p|(t,p))) {
        if segment.last().map(|&(t,p)| pct>p || at-t>12*3600).unwrap_or(false) { segment.clear(); }
        segment.push((at,pct));
    }
    let first=segment.first().copied(); let last=segment.last().copied();
    let span=first.zip(last).map(|(a,b)|(b.0-a.0) as f64/3600.0).unwrap_or(0.0);
    let drop=first.zip(last).map(|(a,b)|a.1-b.1);
    let age=last.map(|p|(now-p.0 as f64)/3600.0);
    let ready=segment.len()>=3 && span>=24.0 && age.map(|h|h<=24.0).unwrap_or(false);
    json!({"status":if ready {"ready"} else {"collecting"},"samples":segment.len(),
        "start_at":first.map(|p|p.0),"end_at":last.map(|p|p.0),"span_hours":span,
        "latest_age_hours":age,"net_drop_points":if ready {drop} else {None},
        "points_per_day":if ready {drop.map(|d|d as f64*24.0/span)} else {None},
        "message":if ready {"Observed net change between saved readings; this does not identify the cause of battery use or predict remaining life."}
        else {"Collecting a recent battery baseline. Needs at least 3 readings spanning 24 hours, without an observed increase or a gap over 12 hours."},
        "method":"Uses the last 72 hours of saved ring readings. Any percentage increase starts a new segment, since charging or measurement variation may have occurred. Changes between readings can be missed. No extra battery polling."})
}

/// Explains estimator eligibility without pretending to diagnose signal loss.
pub(crate) fn staging_diagnostic(duration_min:f64, usable_hr:usize, hrv:usize, motion:usize,
    source:Option<&str>, stage_count:usize, complete:bool) -> Value {
    let (reason,explanation)=if complete {
        ("complete","Every cell in the recorded window has an estimated stage; this does not establish accuracy.")
    } else if stage_count>0 {
        ("partial_existing_staging","Existing staging contains unknown cells. It is preserved rather than overwritten with invented stages.")
    } else if duration_min<60.0 {
        ("short_record","The signal fallback requires a recorded window of at least 60 minutes. This may be a short rest rather than a failed night.")
    } else if usable_hr<12 {
        ("insufficient_hr","The signal fallback requires at least 12 usable heart-rate samples. Missing samples are not converted into sleep stages.")
    } else {
        ("unavailable","No staging result is available despite the basic fallback eligibility checks. Further inspection is needed.")
    };
    json!({"reason":reason,"explanation":explanation,"duration_min":duration_min,
        "usable_hr_samples":usable_hr,"hrv_samples":hrv,"motion_samples":motion,"source":source})
}

fn signal_report(samples: &[(usize,f64)], nights: &[Value], now:f64, tz:f64) -> Value {
    let today=((now+tz*3600.0)/DAY).floor() as i64;
    let cut=(today-6) as f64*DAY-tz*3600.0;
    let windows:Vec<(f64,f64)>=nights.iter().filter_map(|n|n["start_unix"].as_f64().zip(n["end_unix"].as_f64()))
        .filter(|&(s,e)|s.is_finite() && e.is_finite() && e>s && e>=cut && s<=now).collect();
    let mut all:[BTreeSet<i64>;3]=Default::default();
    let mut outside:[BTreeSet<i64>;3]=Default::default();
    let mut latest:Option<f64>=None;
    for &(kind,at) in samples {
        if kind>=3 || !at.is_finite() || at<cut || at>now {continue;}
        let bin=((at+tz*3600.0)/900.0).floor() as i64;
        all[kind].insert(bin);
        latest=Some(latest.map_or(at,|old|old.max(at)));
        if !windows.iter().any(|&(s,e)|at>=s && at<=e) {outside[kind].insert(bin);}
    }
    let overlap=outside[0].iter().filter(|b|outside[1].contains(b) && outside[2].contains(b)).count();
    let rows:Vec<Value>=[("hr","Accepted heart rate"),("hrv","Reported HRV"),("movement","Movement samples")].iter().enumerate()
        .map(|(i,(id,title))|json!({"id":id,"title":title,"bins":all[i].len(),"outside_sleep_bins":outside[i].len()})).collect();
    let recent:Vec<&Value>=nights.iter().filter(|n|n["end_unix"].as_f64().map(|e|e>=cut && e<=now).unwrap_or(false)).collect();
    let records:Vec<Value>=recent.iter().map(|n| {
        let mut d=n["staging_diagnostic"].clone();
        if !d.is_object() { d=json!({"reason":"not_reported","explanation":"Reload to refresh staging diagnostics.","duration_min":0,"usable_hr_samples":0,"hrv_samples":0,"motion_samples":0,"source":null}); }
        d["end_at"]=n["end_unix"].clone();
        d
    }).collect();
    json!({"sleep_records":records,"window_start":cut,"window_end":now,"latest_sample_at":latest,"signals":rows,
        "recorded_nights":recent.len(),"complete_staging_nights":recent.iter().filter(|n|n["staging_complete"].as_bool()==Some(true)).count(),
        "candidate_overlap_bins":overlap,
        "message":"Counts show 15-minute bins containing at least one saved sample, not minutes of continuous recording. Outside recorded sleep windows does not prove wakefulness or ring wear. Overlap in a bin does not establish simultaneous or low-motion measurements. This is not a daytime stress result.",
        "next_step":"Daytime stress still requires signal-quality and movement checks, a daytime baseline, and validated temperature channels. Raw IBI and generic temperature packets are not treated as validated HRV or skin temperature."})
}

pub(crate) fn build(events:&[(i64,u8,String,i64)], clock:&RingClock, nights:&[Value], battery:&[(f64,i64)], now:f64,tz:f64) -> Value {
    let mut samples=Vec::new();
    let cut=now-8.0*DAY; // calendar filter is applied after timezone conversion
    let mut excluded=0;
    for (ds,tag,j,cu) in events {
        let name=oura_protocol::events::event_name(*tag);
        if !matches!(name,"hrv_event"|"green_ibi_quality_event"|"activity_information") {continue;}
        let at=clock.unix_s(*ds,*cu);
        if !clock.resolve(*ds,*cu).source.is_dated() {excluded+=1;continue;}
        if at<cut || at>now {continue;}
        let Ok(v)=serde_json::from_str::<Value>(j) else {continue;};
        if name=="hrv_event" {
            for (field,kind) in [("hr_bpm",0),("rmssd_ms",1)] {
                if let Some(arr)=v[field].as_array() {
                    for (ts,val) in crate::packed_series(*ds,arr,crate::hrv_step_ds(&v)) {
                        if clock.resolve(ts,*cu).source.is_dated() && val.is_finite() && (if kind==0 {(30.0..=240.0).contains(&val)} else {val>0.0}) {
                            samples.push((kind,clock.unix_s(ts,*cu)));
                        }
                    }
                }
            }
        } else if name=="green_ibi_quality_event" {
            if v["hr_bpm"].as_array().map(|a|a.iter().filter_map(Value::as_f64).any(|h|(30.0..=240.0).contains(&h))).unwrap_or(false) {samples.push((0,at));}
        } else if let Some(arr)=v["met"].as_array() {
            for (i,val) in arr.iter().enumerate() {
                if val.as_f64().map(|v|v.is_finite() && v>=0.0).unwrap_or(false) {samples.push((2,clock.unix_s(*ds+i as i64*600,*cu)));}
            }
        }
    }
    json!({"generated_at":now,"battery":battery_report(battery,now),
        "coverage":signal_report(&samples,nights,now,tz),"untrusted_clock_packets":excluded,
        "scope":"Calculated locally from saved data. No extra ring sampling or uploads. Clock exclusions count relevant packets across the saved history."})
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn battery_needs_real_time_span_and_resets_on_rise_or_large_gap() {
        let now=10.0*DAY;
        let good=vec![(now-DAY,80),(now-DAY/2.0,70),(now,60)];
        assert_eq!(battery_report(&good,now)["points_per_day"],20.0);
        let mut charged=good.clone(); charged.push((now+3600.0,90));
        assert!(battery_report(&charged,now+3600.0)["points_per_day"].is_null());
        assert!(battery_report(&[(now-DAY,80),(now-3600.0,70),(now,60)],now)["points_per_day"].is_null());
        assert!(battery_report(&good,now+2.0*DAY)["points_per_day"].is_null());
    }
    #[test] fn battery_duplicates_conflicts_future_and_invalid_readings_are_not_evidence() {
        let now=10.0*DAY;
        let rows=vec![(now-DAY,80),(now-DAY/2.0,70),(now-DAY/2.0,70),(now,60),(now+10.0,1),(now-100.0,101)];
        assert_eq!(battery_report(&rows,now)["samples"],3);
        let mut conflicting=rows;conflicting.push((now-DAY/2.0,71));
        assert!(battery_report(&conflicting,now)["points_per_day"].is_null());
    }
    #[test] fn coverage_counts_bins_not_samples_and_keeps_sleep_and_gaps_distinct() {
        let now=10.0*DAY;
        let nights=vec![json!({"start_unix":now-3600.0,"end_unix":now-1800.0,"staging_complete":true})];
        let s=vec![(0,now-3000.0),(1,now-3000.0),(2,now-3000.0),
            (0,now-600.0),(0,now-601.0),(1,now-600.0),(2,now-600.0),(0,now+1.0),(0,now-8.0*DAY)];
        let x=signal_report(&s,&nights,now,0.0);
        assert_eq!(x["signals"][0]["bins"],2);
        assert_eq!(x["signals"][0]["outside_sleep_bins"],1);
        assert_eq!(x["candidate_overlap_bins"],1);
        assert_eq!(x["complete_staging_nights"],1);
        assert_eq!(signal_report(&[],&[],now,0.0)["signals"][0]["bins"],0);
    }
    #[test] fn staging_reasons_distinguish_short_rest_missing_hr_and_partial_results() {
        assert_eq!(staging_diagnostic(30.0,0,0,0,None,0,false)["reason"],"short_record");
        assert_eq!(staging_diagnostic(480.0,11,2,10,None,0,false)["reason"],"insufficient_hr");
        assert_eq!(staging_diagnostic(480.0,100,50,20,Some("ring"),30,false)["reason"],"partial_existing_staging");
        assert_eq!(staging_diagnostic(480.0,100,50,20,Some("signals"),960,true)["reason"],"complete");
    }
    #[test] fn parser_uses_anchored_packed_times_and_ignores_raw_ibi_and_invalid_hrv() {
        let now=10.0*DAY;
        let events=vec![
            (0,0x42,json!({"unix_time":now as i64-3600}).to_string(),now as i64),
            (18000,0x5d,json!({"interval_min":15,"hr_bpm":[60,61],"rmssd_ms":[30,0]}).to_string(),now as i64),
            (20000,0x60,json!({"hr_bpm":[70],"rmssd_ms":[50]}).to_string(),now as i64),
        ];
        let clock=RingClock::from_events(&events);
        let x=build(&events,&clock,&[],&[],now,0.0);
        assert_eq!(x["coverage"]["signals"][0]["bins"],2);
        assert_eq!(x["coverage"]["signals"][1]["bins"],1);
        assert_eq!(x["coverage"]["signals"][2]["bins"],0);
    }
}
