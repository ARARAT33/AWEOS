pub mod widgets {
    pub struct ClockWidget;
    impl ClockWidget {
        pub fn now_string() -> String {
            use std::time::{SystemTime, UNIX_EPOCH};
            let secs = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
            format!("{:02}:{:02}:{:02} UTC", (secs/3600)%24, (secs/60)%60, secs%60)
        }
    }
    pub struct CpuRamWidget;
    impl CpuRamWidget {
        pub fn get_info() -> (u32,u32) { (Self::cpu().unwrap_or(0), Self::ram().unwrap_or(0)) }
        fn cpu() -> Option<u32> {
            let a=Self::times()?; std::thread::sleep(std::time::Duration::from_millis(50)); let b=Self::times()?;
            let idle=b[3].saturating_sub(a[3]); let total=b.iter().sum::<u64>().saturating_sub(a.iter().sum());
            if total==0 {Some(0)} else {Some(((total.saturating_sub(idle)*100)/total).min(100) as u32)}
        }
        fn times()->Option<[u64;4]> {
            let s=std::fs::read_to_string("/proc/stat").ok()?; let l=s.lines().find(|x|x.starts_with("cpu "))?;
            let mut v=l.split_whitespace().skip(1).take(4);
            Some([v.next()?.parse().ok()?,v.next()?.parse().ok()?,v.next()?.parse().ok()?,v.next()?.parse().ok()?])
        }
        fn ram()->Option<u32> {
            let s=std::fs::read_to_string("/proc/meminfo").ok()?;
            let mut t: u64=0;
            let mut a: u64=0;
            for l in s.lines() {
                let mut p=l.split_whitespace();
                match p.next()? {
                    "MemTotal:"=>t=p.next()?.parse().ok()?,
                    "MemAvailable:"=>a=p.next()?.parse().ok()?,
                    _=>{}
                }
            }
            if t==0 {None} else {Some(((t.saturating_sub(a)*100/t).min(100)) as u32)}
        }
    }
    pub struct NetworkWidget;
    impl NetworkWidget {
        pub fn status()->String {
            let mut up=Vec::new();
            if let Ok(es)=std::fs::read_dir("/sys/class/net") { for e in es.flatten() {
                let n=e.file_name().to_string_lossy().into_owned(); if n=="lo" {continue;}
                if std::fs::read_to_string(e.path().join("operstate")).unwrap_or_default().trim()=="up" {up.push(n);}
            }}
            if up.is_empty() {"Network: offline".into()} else {format!("Connected: {}",up.join(", "))}
        }
    }
    pub struct BatteryWidget;
    impl BatteryWidget {
        pub fn status()->String {
            if let Ok(es)=std::fs::read_dir("/sys/class/power_supply") { for e in es.flatten() {
                let p=e.path(); if std::fs::read_to_string(p.join("type")).unwrap_or_default().trim()=="Battery" {
                    let c=std::fs::read_to_string(p.join("capacity")).unwrap_or_default();
                    let s=std::fs::read_to_string(p.join("status")).unwrap_or_default();
                    return format!("Battery: {}% ({})",c.trim(),s.trim());
                }
            }}
            "Battery: AC".into()
        }
    }
}
pub struct Panel { pub height:u32, pub position:String }
impl Panel {
    pub fn new(height:u32,position:&str)->Self {Self{height,position:position.into()}}
    pub fn widget_order(&self)->Vec<&'static str> {vec!["launcher","workspaces","window-list","network","volume","battery","clock","control-center"]}
}
