// Contrôle : notre secret client Apple est-il accepté ?
//
// On refabrique le JWT exactement comme la Lambda, et on présente un code
// volontairement faux. La réponse d'Apple dit tout :
//   invalid_grant  → notre identité est bonne, seul le code est mauvais ✓
//   invalid_client → la clé, le Team ID, le Key ID ou l'App ID ne va pas ✗
#[tokio::main]
async fn main() {
    let team = std::env::var("APPLE_TEAM_ID").unwrap();
    let kid = std::env::var("APPLE_KEY_ID").unwrap();
    let client = std::env::var("APPLE_CLIENT_ID").unwrap();
    let key_path = std::env::var("APPLE_KEY_PATH").unwrap();
    let key = std::fs::read_to_string(&key_path).unwrap();

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    #[derive(serde::Serialize)]
    struct Claims<'a> {
        iss: &'a str,
        iat: i64,
        exp: i64,
        aud: &'a str,
        sub: &'a str,
    }

    let mut header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::ES256);
    header.kid = Some(kid.clone());
    let signing = jsonwebtoken::EncodingKey::from_ec_pem(key.as_bytes()).unwrap();

    let secret = jsonwebtoken::encode(
        &header,
        &Claims {
            iss: &team,
            iat: now,
            exp: now + 3600,
            aud: "https://appleid.apple.com",
            sub: &client,
        },
        &signing,
    )
    .unwrap();

    println!("secret client signé ✓  (ES256, kid = {kid})");

    let body = reqwest::Client::new()
        .post("https://appleid.apple.com/auth/token")
        .form(&[
            ("client_id", client.as_str()),
            ("client_secret", secret.as_str()),
            ("code", "code-volontairement-invalide"),
            ("grant_type", "authorization_code"),
        ])
        .send()
        .await
        .unwrap();

    let status = body.status();
    let text = body.text().await.unwrap();
    println!("réponse d'Apple : {status} {text}\n");

    if text.contains("invalid_grant") {
        println!("  ✓ PARFAIT — Apple a accepté notre identité (clé, Team ID, Key ID,");
        println!("    App ID tous corrects) et n'a refusé que le faux code.");
    } else if text.contains("invalid_client") {
        println!("  ✗ Apple refuse notre identité : une des quatre valeurs ne va pas.");
    }
}
