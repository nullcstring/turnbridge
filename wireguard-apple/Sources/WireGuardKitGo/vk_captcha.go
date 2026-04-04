package main

import (
    "context"
    "crypto/rand"
    "crypto/sha256"
    "crypto/tls"
    "encoding/base64"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "io"
    "log"
    mathrand "math/rand"
    "net"
    "net/http"
    "net/url"
    "regexp"
    "strconv"
    "strings"
    "sync"
    "time"
)

var captchaMu sync.Mutex

func init() {
    mathrand.Seed(time.Now().UnixNano())
}

func randomHex(n int) string {
    bytes := make([]byte, n)
    if _, err := rand.Read(bytes); err != nil {
        // Fallback
        for i := range bytes {
            bytes[i] = byte(mathrand.Intn(256))
        }
    }
    return hex.EncodeToString(bytes)
}

type VkCaptchaError struct {
    ErrorCode               int
    ErrorMsg                string
    CaptchaSid              string
    CaptchaImg              string
    RedirectUri             string
    IsSoundCaptchaAvailable bool
    SessionToken            string
    CaptchaTs               string
    CaptchaAttempt          string
}

func ParseVkCaptchaError(errData map[string]interface{}) *VkCaptchaError {
    codeFloat, _ := errData["error_code"].(float64)
    code := int(codeFloat)

    redirectUri, _ := errData["redirect_uri"].(string)
    captchaSid, _ := errData["captcha_sid"].(string)
    captchaImg, _ := errData["captcha_img"].(string)
    errorMsg, _ := errData["error_msg"].(string)

    var sessionToken string
    if redirectUri != "" {
        if parsed, err := url.Parse(redirectUri); err == nil {
            sessionToken = parsed.Query().Get("session_token")
        }
    }

    isSound, _ := errData["is_sound_captcha_available"].(bool)

    var captchaTs string
    if tsFloat, ok := errData["captcha_ts"].(float64); ok {
        captchaTs = fmt.Sprintf("%.0f", tsFloat)
    } else if tsStr, ok := errData["captcha_ts"].(string); ok {
        captchaTs = tsStr
    }

    var captchaAttempt string
    if attFloat, ok := errData["captcha_attempt"].(float64); ok {
        captchaAttempt = fmt.Sprintf("%.0f", attFloat)
    } else if attStr, ok := errData["captcha_attempt"].(string); ok {
        captchaAttempt = attStr
    }

    return &VkCaptchaError{
        ErrorCode:               code,
        ErrorMsg:                errorMsg,
        CaptchaSid:              captchaSid,
        CaptchaImg:              captchaImg,
        RedirectUri:             redirectUri,
        IsSoundCaptchaAvailable: isSound,
        SessionToken:            sessionToken,
        CaptchaTs:               captchaTs,
        CaptchaAttempt:          captchaAttempt,
    }
}

func (e *VkCaptchaError) IsCaptchaError() bool {
    return e.ErrorCode == 14 && e.RedirectUri != "" && e.SessionToken != ""
}

func solveVkCaptcha(ctx context.Context, captchaErr *VkCaptchaError) (string, error) {
    captchaMu.Lock()
    defer captchaMu.Unlock()
    
    time.Sleep(time.Duration(1500 + mathrand.Intn(1000)) * time.Millisecond)

    log.Printf("[Captcha] Solving Not Robot Captcha...")

    sessionToken := captchaErr.SessionToken
    if sessionToken == "" {
        return "", fmt.Errorf("no session_token in redirect_uri")
    }

    powInput, difficulty, cookies, err := fetchPowInput(ctx, captchaErr.RedirectUri)
    if err != nil {
        return "", fmt.Errorf("failed to fetch PoW input: %w", err)
    }

    log.Printf("[Captcha] PoW input: %s, difficulty: %d", powInput, difficulty)

    hash := solvePoW(powInput, difficulty)
    log.Printf("[Captcha] PoW solved: hash=%s", hash)

    successToken, err := callCaptchaNotRobot(ctx, sessionToken, hash, cookies)
    if err != nil {
        return "", fmt.Errorf("captchaNotRobot API failed: %w", err)
    }

    log.Printf("[Captcha] Success! Got success_token")
    return successToken, nil
}

func fetchPowInput(ctx context.Context, redirectUri string) (string, int, string, error) {
    req, err := http.NewRequestWithContext(ctx, "GET", redirectUri, nil)
    if err != nil {
        return "", 0, "", err
    }
    
    req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36")
    req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    req.Header.Set("Accept-Language", "en-US,en;q=0.9")

    client := &http.Client{
        Timeout: 20 * time.Second,
        Transport: &http.Transport{
            DialContext: (&net.Dialer{
                Timeout:   30 * time.Second,
                KeepAlive: 30 * time.Second,
            }).DialContext,
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: false,
            },
        },
    }

    resp, err := client.Do(req)
    if err != nil {
        return "", 0, "", err
    }
    defer resp.Body.Close()

    var cookies []string
    for _, setCookie := range resp.Header.Values("Set-Cookie") {
        cookieParts := strings.Split(setCookie, ";")
        cookies = append(cookies, strings.TrimSpace(cookieParts[0]))
    }
    cookieHeader := strings.Join(cookies, "; ")

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return "", 0, "", err
    }

    html := string(body)

    powInputRe := regexp.MustCompile(`const\s+powInput\s*=\s*"([^"]+)"`)
    powInputMatch := powInputRe.FindStringSubmatch(html)
    if len(powInputMatch) < 2 {
        return "", 0, "", fmt.Errorf("powInput not found in captcha HTML")
    }
    powInput := powInputMatch[1]

    diffRe := regexp.MustCompile(`startsWith\('0'\.repeat\((\d+)\)\)`)
    diffMatch := diffRe.FindStringSubmatch(html)
    difficulty := 2
    if len(diffMatch) >= 2 {
        if d, err := strconv.Atoi(diffMatch[1]); err == nil {
            difficulty = d
        }
    }

    return powInput, difficulty, cookieHeader, nil
}

func solvePoW(powInput string, difficulty int) string {
    target := strings.Repeat("0", difficulty)

    for nonce := 1; nonce <= 10000000; nonce++ {
        data := powInput + strconv.Itoa(nonce)
        hash := sha256.Sum256([]byte(data))
        hexHash := hex.EncodeToString(hash[:])

        if strings.HasPrefix(hexHash, target) {
            return hexHash
        }
    }
    return ""
}

func callCaptchaNotRobot(ctx context.Context, sessionToken, hash, cookies string) (string, error) {
    vkReq := func(method string, postData string) (map[string]interface{}, error) {
        requestURL := "https://api.vk.ru/method/" + method + "?v=5.131"

        req, err := http.NewRequestWithContext(ctx, "POST", requestURL, strings.NewReader(postData))
        if err != nil {
            return nil, err
        }
        
        req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36")
        req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
        req.Header.Set("Accept", "*/*")
        req.Header.Set("Accept-Language", "en-US,en;q=0.9")
        req.Header.Set("Origin", "https://id.vk.ru")
        req.Header.Set("Referer", "https://id.vk.ru/")
        req.Header.Set("sec-ch-ua-platform", `"Windows"`)
        req.Header.Set("sec-ch-ua", `"Chromium";v="146", "Not-A.Brand";v="24", "Google Chrome";v="146"`)
        req.Header.Set("sec-ch-ua-mobile", "?0")
        req.Header.Set("Sec-Fetch-Site", "same-site")
        req.Header.Set("Sec-Fetch-Mode", "cors")
        req.Header.Set("Sec-Fetch-Dest", "empty")
        req.Header.Set("DNT", "1")
        req.Header.Set("Priority", "u=1, i")

        if cookies != "" {
			req.Header.Set("Cookie", cookies)
		}

        client := &http.Client{
            Timeout: 20 * time.Second,
            Transport: &http.Transport{
                DialContext: (&net.Dialer{
                    Timeout:   30 * time.Second,
                    KeepAlive: 30 * time.Second,
                }).DialContext,
            },
        }

        httpResp, err := client.Do(req)
        if err != nil {
            return nil, err
        }
        defer httpResp.Body.Close()

        body, err := io.ReadAll(httpResp.Body)
        if err != nil {
            return nil, err
        }

        var resp map[string]interface{}
        if err := json.Unmarshal(body, &resp); err != nil {
            return nil, err
        }

        return resp, nil
    }

    domain := "vk.com"
    baseParams := fmt.Sprintf("session_token=%s&domain=%s&adFp=&access_token=",
        url.QueryEscape(sessionToken), url.QueryEscape(domain))

    log.Printf("[Captcha] Step 1/4: settings")
    _, err := vkReq("captchaNotRobot.settings", baseParams)
    if err != nil {
        return "", fmt.Errorf("settings failed: %w", err)
    }
    time.Sleep(time.Duration(100 + mathrand.Intn(100)) * time.Millisecond)

    log.Printf("[Captcha] Step 2/4: componentDone")
    
    browserFp := fmt.Sprintf("%016x%016x", mathrand.Int63(), mathrand.Int63())
    
    resolutions := [][]int{{1920, 1080}, {1366, 768}, {1440, 900}, {1536, 864}, {2560, 1440}}
    res := resolutions[mathrand.Intn(len(resolutions))]
    screenW, screenH := res[0], res[1]
    
    cores := []int{4, 8, 12, 16}[mathrand.Intn(4)]
    ram := []int{4, 8, 16, 32}[mathrand.Intn(4)]

    deviceMap := map[string]interface{}{
        "screenWidth": screenW,
        "screenHeight": screenH,
        "screenAvailWidth": screenW,
        "screenAvailHeight": screenH - 40,
        "innerWidth": screenW - mathrand.Intn(100),
        "innerHeight": screenH - 100 - mathrand.Intn(50),
        "devicePixelRatio": []float64{1, 1.25, 1.5, 2}[mathrand.Intn(4)],
        "language": "en-US",
        "languages": []string{"en-US", "en"},
        "webdriver": false,
        "hardwareConcurrency": cores,
        "deviceMemory": ram,
        "connectionEffectiveType": "4g",
        "notificationsPermission": "denied",
    }
    deviceBytes, _ := json.Marshal(deviceMap)

    componentDoneData := baseParams + fmt.Sprintf("&browser_fp=%s&device=%s",
        browserFp, url.QueryEscape(string(deviceBytes)))

    _, err = vkReq("captchaNotRobot.componentDone", componentDoneData)
    if err != nil {
        return "", fmt.Errorf("componentDone failed: %w", err)
    }
    time.Sleep(time.Duration(1500 + mathrand.Intn(1000)) * time.Millisecond)

    log.Printf("[Captcha] Step 3/4: check")
    
    type Point struct {
        X int `json:"x"`
        Y int `json:"y"`
    }
    var cursor []Point
    startX, startY := screenW/2 + mathrand.Intn(200)-100, screenH/2 + mathrand.Intn(200)-100
    
    pointsCount := 4 + mathrand.Intn(5) 
    for i := 0; i < pointsCount; i++ {
        cursor = append(cursor, Point{X: startX, Y: startY})
        startX += mathrand.Intn(30) - 15
        startY += mathrand.Intn(30) - 15
    }
    cursorBytes, _ := json.Marshal(cursor)

	baseDownlink := 8.0 + mathrand.Float64()*4.0
	downlinkStr := fmt.Sprintf("%.1f", baseDownlink)
	connectionDownlink := "[" + downlinkStr + "," + downlinkStr + "," + downlinkStr + "," + downlinkStr + "," + downlinkStr + "," + downlinkStr + "," + downlinkStr + "]"

    answer := base64.StdEncoding.EncodeToString([]byte("{}"))
    
    debugInfo := randomHex(32)

    checkData := baseParams + fmt.Sprintf(
        "&accelerometer=%s&gyroscope=%s&motion=%s&cursor=%s&taps=%s&connectionRtt=%s&connectionDownlink=%s"+
            "&browser_fp=%s&hash=%s&answer=%s&debug_info=%s",
        url.QueryEscape("[]"),
        url.QueryEscape("[]"),
        url.QueryEscape("[]"),
        url.QueryEscape(string(cursorBytes)),
        url.QueryEscape("[]"),
        url.QueryEscape("[]"),
        url.QueryEscape(string(connectionDownlink)),
        browserFp,
        hash,
        answer,
        debugInfo,
    )

    checkResp, err := vkReq("captchaNotRobot.check", checkData)
    if err != nil {
        return "", fmt.Errorf("check failed: %w", err)
    }

    respObj, ok := checkResp["response"].(map[string]interface{})
    if !ok {
        return "", fmt.Errorf("invalid check response: %v", checkResp)
    }

    status, _ := respObj["status"].(string)
    if status != "OK" {
        return "", fmt.Errorf("check response status: %s, full response: %v", status, checkResp)
    }

    successToken, ok := respObj["success_token"].(string)
    if !ok || successToken == "" {
        return "", fmt.Errorf("success_token not found in check response: %v", checkResp)
    }

    log.Printf("[Captcha] Step 4/4: endSession")
    _, err = vkReq("captchaNotRobot.endSession", baseParams)
    if err != nil {
        log.Printf("[Captcha] Warning: endSession failed: %v", err)
    }

    return successToken, nil
}
