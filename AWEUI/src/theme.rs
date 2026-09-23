#[derive(Debug, Clone)]
pub struct Theme {
    pub name: String,
    pub background: [f32;4],
    pub panel: [f32;4],
    pub surface: [f32;4],
    pub text: [f32;4],
    pub muted: [f32;4],
    pub accent: [f32;4],
    pub danger: [f32;4],
    pub radius: f32,
    pub panel_height: u32,
}

impl Theme {
    pub fn dark() -> Self {
        Self {
            name:"AWEUI-Dark".into(),
            background:[0.059,0.090,0.165,1.0],
            panel:[0.118,0.161,0.224,0.97],
            surface:[0.09,0.12,0.18,0.98],
            text:[0.973,0.98,0.988,1.0],
            muted:[0.58,0.64,0.72,1.0],
            accent:[0.231,0.510,0.965,1.0],
            danger:[0.94,0.32,0.32,1.0],
            radius:10.0,
            panel_height:36,
        }
    }
    pub fn light() -> Self {
        Self {
            name:"AWEUI-Light".into(),
            background:[0.95,0.96,0.98,1.0],
            panel:[0.99,0.995,1.0,0.96],
            surface:[1.0,1.0,1.0,0.98],
            text:[0.08,0.10,0.14,1.0],
            muted:[0.35,0.40,0.48,1.0],
            accent:[0.13,0.38,0.86,1.0],
            danger:[0.78,0.15,0.15,1.0],
            radius:10.0,
            panel_height:36,
        }
    }
    pub fn from_name(name:&str)->Self {
        if name.eq_ignore_ascii_case("AWEUI-Light") { Self::light() } else { Self::dark() }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn themes_have_accessible_structure(){ let d=Theme::dark(); let l=Theme::light(); assert_eq!(d.panel_height,36); assert_ne!(d.background,l.background); }
}
