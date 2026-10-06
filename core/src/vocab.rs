//! Custom vocabulary management (ChiaKey integration): custom words stored in `custom_vocab.tsv`.
//! Format: one record per line, two tab-separated fields: reading (syllables joined by `-`), word.
//! Priority is derived from the order in the file (earlier lines have higher priority).

use std::fmt::Write as _;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

pub const FILE: &str = "custom_vocab.tsv";
pub const HEADER: &str = "#shanjie-custom-vocab v1";
pub const MAX_BYTES: u64 = 2 * 1024 * 1024; // 2 MB limit for custom vocabulary

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CustomWord {
    pub reading: Vec<String>,
    pub word: String,
}

#[derive(Clone, Debug)]
pub struct VocabStore {
    dir: PathBuf,
    words: Vec<CustomWord>,
}

fn clean(s: &str) -> bool {
    !s.is_empty() && !s.chars().any(char::is_control)
}

fn parse_line(line: &str) -> Option<CustomWord> {
    let f: Vec<&str> = line.split('\t').collect();
    if f.len() != 2 {
        return None;
    }
    let reading = f[0].split('-').map(str::to_string).collect::<Vec<String>>();
    if reading.is_empty() || reading.iter().any(|s| s.is_empty() || s.contains('-')) {
        return None;
    }
    if !clean(f[1]) {
        return None;
    }
    Some(CustomWord {
        reading,
        word: f[1].to_string(),
    })
}

impl VocabStore {
    pub fn open(dir: &Path) -> Result<VocabStore, std::io::Error> {
        let mut words = Vec::new();
        let path = dir.join(FILE);
        match File::open(&path) {
            Ok(f) => {
                let reader = BufReader::new(f);
                for (i, line) in reader.lines().enumerate() {
                    let line = line?;
                    if i == 0 && line == HEADER {
                        continue;
                    }
                    if let Some(w) = parse_line(&line) {
                        words.push(w);
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        Ok(VocabStore {
            dir: dir.to_path_buf(),
            words,
        })
    }

    pub fn save(&self) -> Result<(), std::io::Error> {
        let mut buf = String::new();
        buf.push_str(HEADER);
        buf.push('\n');
        for w in &self.words {
            let _ = writeln!(buf, "{}\t{}", w.reading.join("-"), w.word);
        }
        let tmp = self.dir.join(format!("{}.tmp", FILE));
        let mut f = File::create(&tmp)?;
        f.write_all(buf.as_bytes())?;
        fs::rename(&tmp, self.dir.join(FILE))?;
        Ok(())
    }

    pub fn add(&mut self, reading: Vec<String>, word: String) -> bool {
        if self
            .words
            .iter()
            .any(|w| w.reading == reading && w.word == word)
        {
            return false;
        }
        self.words.push(CustomWord { reading, word });
        true
    }

    pub fn remove(&mut self, reading: &Vec<String>, word: &str) -> bool {
        let pos = self
            .words
            .iter()
            .position(|w| w.reading == *reading && w.word == word);
        if let Some(i) = pos {
            self.words.remove(i);
            true
        } else {
            false
        }
    }

    pub fn words(&self) -> &[CustomWord] {
        &self.words
    }

    pub fn find(&self, reading: &[String]) -> Vec<&CustomWord> {
        self.words
            .iter()
            .filter(|w| w.reading == *reading)
            .collect()
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }
}

/// Import Yahoo! KeyKey export format (MJSR version 1.0.0).
/// Format: text lines "phrase<TAB>reading<TAB>probability<TAB>backoff"
pub fn import_keykey_export(path: &Path) -> Result<Vec<CustomWord>, std::io::Error> {
    let mut words = Vec::new();
    let f = File::open(path)?;
    let reader = BufReader::new(f);
    for line in reader.lines() {
        let line = line?;
        if line.starts_with("MJSR version")
            || line.starts_with('#')
            || line.starts_with("<database>")
            || line.starts_with("</database>")
        {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 2 {
            continue;
        }
        let phrase = fields[0];
        let reading_str = fields[1];
        let reading = reading_str
            .split('-')
            .map(str::to_string)
            .collect::<Vec<String>>();
        if !reading.is_empty() && !phrase.is_empty() {
            words.push(CustomWord {
                reading,
                word: phrase.to_string(),
            });
        }
    }
    Ok(words)
}

/// Import .cin table format (CangJie input method table).
/// Format: lines like "aamh  暘" where first field is key sequence and second is character.
pub fn import_cin_table(path: &Path) -> Result<Vec<CustomWord>, std::io::Error> {
    let mut words = Vec::new();
    let f = File::open(path)?;
    let reader = BufReader::new(f);
    let mut in_chardef = false;
    for line in reader.lines() {
        let line = line?;
        if line.starts_with("%chardef begin") {
            in_chardef = true;
            continue;
        }
        if line.starts_with("%chardef end") || line.starts_with("%endkey") {
            in_chardef = false;
            continue;
        }
        if !in_chardef {
            continue;
        }
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 {
            let key = parts[0];
            let char_str = parts[1];
            // Convert CangJie key sequence to a reading (simplified: use the key as reading)
            let reading = vec![key.to_string()];
            words.push(CustomWord {
                reading,
                word: char_str.to_string(),
            });
        }
    }
    Ok(words)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_dir() -> PathBuf {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let d = std::env::temp_dir().join(format!(
            "shanjie-vocab-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn test_parse_custom_vocab() {
        let d = temp_dir();
        let path = d.join(FILE);
        fs::write(
            &path,
            "#shanjie-custom-vocab v1\nㄅㄚˇ-ㄅㄚˇ\t把手\nㄐㄧㄣ-ㄊㄧㄢ\t今天\n",
        )
        .unwrap();
        let store = VocabStore::open(&d).unwrap();
        // Debug: print the words to understand what's happening
        eprintln!("Words: {:?}", store.words);
        assert_eq!(store.words.len(), 2);
        assert_eq!(store.words[0].word, "把手");
        assert_eq!(store.words[1].word, "今天");
    }

    #[test]
    fn test_add_and_remove() {
        let d = temp_dir();
        let mut store = VocabStore::open(&d).unwrap();
        assert!(store.add(vec!["ㄓㄨㄥ".to_string()], "重".to_string()));
        assert!(!store.add(vec!["ㄓㄨㄥ".to_string()], "重".to_string())); // duplicate
        assert!(store.remove(&vec!["ㄓㄨㄥ".to_string()], "重"));
        assert!(!store.remove(&vec!["ㄓㄨㄥ".to_string()], "重")); // already removed
    }

    #[test]
    fn test_save_and_load() {
        let d = temp_dir();
        let mut store = VocabStore::open(&d).unwrap();
        store.add(vec!["ㄅㄚˇ".to_string()], "吧".to_string());
        store.save().unwrap();
        let store2 = VocabStore::open(&d).unwrap();
        assert_eq!(store2.words.len(), 1);
        assert_eq!(store2.words[0].word, "吧");
    }

    #[test]
    fn test_empty_and_invalid_lines() {
        let d = temp_dir();
        let path = d.join(FILE);
        // Header + empty line + line without tab + line with only reading (no word)
        fs::write(
            &path,
            "#shanjie-custom-vocab v1\n\nbad line without tab\nㄅㄚˇ",
        )
        .unwrap();
        let store = VocabStore::open(&d).unwrap();
        assert_eq!(store.words.len(), 0); // invalid lines are skipped
    }

    #[test]
    fn test_find_words_by_reading() {
        let d = temp_dir();
        let mut store = VocabStore::open(&d).unwrap();
        store.add(vec!["ㄅㄚˇ-ㄅㄚˇ".to_string()], "把手".to_string());
        store.add(vec!["ㄅㄚˇ-ㄅㄚˇ".to_string()], "把".to_string());
        store.add(vec!["ㄐㄧㄣ-ㄊㄧㄢ".to_string()], "今天".to_string());
        let found = store.find(&vec!["ㄅㄚˇ-ㄅㄚˇ".to_string()]);
        assert_eq!(found.len(), 2);
        let words: Vec<&String> = found.iter().map(|w| &w.word).collect();
        assert!(words.contains(&&"把手".to_string()));
        assert!(words.contains(&&"把".to_string()));
    }

    #[test]
    fn test_import_keykey_format() {
        let d = temp_dir();
        let path = d.join("export.mjsr");
        fs::write(&path, "MJSR version 1.0.0\n把手\tㄅㄚˇ-ㄅㄚˇ\t-1.0\t0.0\n今天\tㄐㄧㄣ-ㄊㄧㄢ\t-1.0\t0.0\n# What follows is the \"Automatic Learning\" database\n<database>\n</database>\n").unwrap();
        let words = import_keykey_export(&path).unwrap();
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].word, "把手");
        assert_eq!(words[1].word, "今天");
    }

    #[test]
    fn test_import_cin_format() {
        let d = temp_dir();
        let path = d.join("test.cin");
        fs::write(
            &path,
            "%gen_inp\n%keyname begin\na 日\nb 月\n%chardef begin\naa 昌\nab 明\n%chardef end\n",
        )
        .unwrap();
        let words = import_cin_table(&path).unwrap();
        assert!(!words.is_empty());
        let has_ming = words.iter().any(|w| w.word == "明");
        assert!(has_ming);
    }
}
