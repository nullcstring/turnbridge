package main

/*
#include <stdlib.h>

typedef void(*proxy_logger_fn_t)(void *context, int level, const char *msg);

static inline void call_proxy_logger(proxy_logger_fn_t fn, void *ctx, int level, const char *msg) {
    if (fn != NULL) {
        fn(ctx, level, msg);
    }
}
*/
import "C" 

import (
    "bytes"
    "context"
    "crypto/tls"
    "encoding/json"
    "fmt"
    "io"
    "log"
    "net"
    "net/http"
    "sync"
    "sync/atomic"
    "time"
    "unsafe"

    "github.com/cbeuw/connutil"
    "github.com/google/uuid"
    "github.com/pion/dtls/v3"
    "github.com/pion/dtls/v3/pkg/crypto/selfsign"
    "github.com/pion/logging"
    "github.com/pion/turn/v4"
)

var proxyLoggerFunc C.proxy_logger_fn_t
var proxyLoggerCtx unsafe.Pointer
var proxyCancel context.CancelFunc

//export ProxySetLogger
func ProxySetLogger(context unsafe.Pointer, loggerFn C.proxy_logger_fn_t) {
    proxyLoggerCtx = context
    proxyLoggerFunc = loggerFn
}

var proxyReady = make(chan struct{}, 1)

//export ProxyWaitReady
func ProxyWaitReady(timeoutMs C.int) C.int {
    select {
    case <-proxyReady:
        return 1
    case <-time.After(time.Duration(timeoutMs) * time.Millisecond):
        return 0
    }
}

type ProxyLogger int

func (l ProxyLogger) Write(p []byte) (n int, err error) {
    if proxyLoggerFunc == nil {
        return len(p), nil
    }

    cleanMsg := bytes.TrimRight(p, "\n")
    cMsg := C.CString(string(cleanMsg))
    defer C.free(unsafe.Pointer(cMsg))

    C.call_proxy_logger(proxyLoggerFunc, proxyLoggerCtx, C.int(l), cMsg)

    return len(p), nil
}

func init() {
    log.SetFlags(0)
    log.SetOutput(ProxyLogger(0))
}

func doRequest(data string, url string) (resp map[string]interface{}, err error) {
    client := &http.Client{
        Timeout: 20 * time.Second,
        Transport: &http.Transport{
            MaxIdleConns:        100,
            MaxIdleConnsPerHost: 100,
            IdleConnTimeout:     90 * time.Second,
        },
    }
    req, err := http.NewRequest("POST", url, bytes.NewBuffer([]byte(data)))
    if err != nil {
        return nil, err
    }

    req.Header.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) Gecko/20100101 Firefox/144.0")
    req.Header.Add("Content-Type", "application/x-www-form-urlencoded")

    httpResp, err := client.Do(req)
    if err != nil {
        return nil, err
    }
    defer httpResp.Body.Close()

    body, err := io.ReadAll(httpResp.Body)
    if err != nil {
        return nil, err
    }

    err = json.Unmarshal(body, &resp)
    if err != nil {
        return nil, err
    }

    return resp, nil
}

func getCreds(link string) (resUser string, resPass string, resTurn string, resErr error) {
    var resp map[string]interface{}
    defer func() {
        if r := recover(); r != nil {
            log.Printf("get TURN creds error (bad JSON?): %v\n\n", resp)
            resErr = fmt.Errorf("panic in getCreds: %v", r)
        }
    }()

    data := "client_secret=QbYic1K3lEV5kTGiqlq2&client_id=6287487&scopes=audio_anonymous%2Cvideo_anonymous%2Cphotos_anonymous%2Cprofile_anonymous&isApiOauthAnonymEnabled=false&version=1&app_id=6287487"
    url := "https://login.vk.ru/?act=get_anonym_token"

    resp, err := doRequest(data, url)
    if err != nil {
        return "", "", "", fmt.Errorf("request error:%s", err)
    }

    token1 := resp["data"].(map[string]interface{})["access_token"].(string)

    data = fmt.Sprintf("access_token=%s", token1)
    url = "https://api.vk.ru/method/calls.getAnonymousAccessTokenPayload?v=5.264&client_id=6287487"

    resp, err = doRequest(data, url)
    if err != nil {
        return "", "", "", fmt.Errorf("request error:%s", err)
    }

    token2 := resp["response"].(map[string]interface{})["payload"].(string)

    data = fmt.Sprintf("client_id=6287487&token_type=messages&payload=%s&client_secret=QbYic1K3lEV5kTGiqlq2&version=1&app_id=6287487", token2)
    url = "https://login.vk.ru/?act=get_anonym_token"

    resp, err = doRequest(data, url)
    if err != nil {
        return "", "", "", fmt.Errorf("request error:%s", err)
    }

    token3 := resp["data"].(map[string]interface{})["access_token"].(string)

    data = fmt.Sprintf("vk_join_link=https://vk.com/call/join/%s&name=123&access_token=%s", link, token3)
    url = "https://api.vk.ru/method/calls.getAnonymousToken?v=5.264"

    resp, err = doRequest(data, url)
    if err != nil {
        return "", "", "", fmt.Errorf("request error:%s", err)
    }

    token4 := resp["response"].(map[string]interface{})["token"].(string)

    data = fmt.Sprintf("%s%s%s", "session_data=%7B%22version%22%3A2%2C%22device_id%22%3A%22", uuid.New(), "%22%2C%22client_version%22%3A1.1%2C%22client_type%22%3A%22SDK_JS%22%7D&method=auth.anonymLogin&format=JSON&application_key=CGMMEJLGDIHBABABA")
    url = "https://calls.okcdn.ru/fb.do"

    resp, err = doRequest(data, url)
    if err != nil {
        return "", "", "", fmt.Errorf("request error:%s", err)
    }

    token5 := resp["session_key"].(string)

    data = fmt.Sprintf("joinLink=%s&isVideo=false&protocolVersion=5&anonymToken=%s&method=vchat.joinConversationByLink&format=JSON&application_key=CGMMEJLGDIHBABABA&session_key=%s", link, token4, token5)
    url = "https://calls.okcdn.ru/fb.do"

    resp, err = doRequest(data, url)
    if err != nil {
        return "", "", "", fmt.Errorf("request error:%s", err)
    }

    user := resp["turn_server"].(map[string]interface{})["username"].(string)
    pass := resp["turn_server"].(map[string]interface{})["credential"].(string)
    turn := resp["turn_server"].(map[string]interface{})["urls"].([]interface{})[0].(string)

    return user, pass, turn, nil
}

func dtlsFunc(ctx context.Context, conn net.PacketConn, peer *net.UDPAddr) (net.Conn, error) {
    certificate, err := selfsign.GenerateSelfSigned()
    if err != nil {
        return nil, err
    }
    config := &dtls.Config{
        Certificates:          []tls.Certificate{certificate},
        InsecureSkipVerify:    true,
        ExtendedMasterSecret:  dtls.RequireExtendedMasterSecret,
        CipherSuites:          []dtls.CipherSuiteID{dtls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256},
        ConnectionIDGenerator: dtls.OnlySendCIDGenerator(),
    }
    ctx1, cancel := context.WithTimeout(ctx, 30*time.Second)
    defer cancel()
    dtlsConn, err := dtls.Client(conn, peer, config)
    if err != nil {
        return nil, err
    }

    if err := dtlsConn.HandshakeContext(ctx1); err != nil {
        return nil, err
    }
    return dtlsConn, nil
}

func oneDtlsConnection(ctx context.Context, peer *net.UDPAddr, listenConn net.PacketConn, connchan chan<- net.PacketConn, okchan chan<- struct{}, c1 chan<- error) {
    var err error = nil
    defer func() { c1 <- err }()
    dtlsctx, dtlscancel := context.WithCancel(ctx)
    defer dtlscancel()
    var conn1, conn2 net.PacketConn
    conn1, conn2 = connutil.AsyncPacketPipe()
    go func() {
        for {
            select {
            case <-dtlsctx.Done():
                return
            case connchan <- conn2:
            }
        }
    }()
    dtlsConn, err1 := dtlsFunc(dtlsctx, conn1, peer)
    if err1 != nil {
        err = fmt.Errorf("failed to connect DTLS: %s", err1)
        return
    }
    defer func() {
        if closeErr := dtlsConn.Close(); closeErr != nil {
            err = fmt.Errorf("failed to close DTLS connection: %s", closeErr)
            return
        }
        log.Printf("Closed DTLS connection\n")
    }()
    log.Printf("Established DTLS connection!\n")
    select { case proxyReady <- struct{}{}: default: }
    go func() {
        for {
            select {
            case <-dtlsctx.Done():
                return
            case okchan <- struct{}{}:
            }
        }
    }()

    wg := sync.WaitGroup{}
    wg.Add(2)
    context.AfterFunc(dtlsctx, func() {
        listenConn.SetDeadline(time.Now())
        dtlsConn.SetDeadline(time.Now())
    })
    var addr atomic.Value
    go func() {
        defer wg.Done()
        defer dtlscancel()
        buf := make([]byte, 1600)
        for {
            select {
            case <-dtlsctx.Done():
                return
            default:
            }
            n, addr1, err1 := listenConn.ReadFrom(buf)
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }

            addr.Store(addr1)

            _, err1 = dtlsConn.Write(buf[:n])
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }
        }
    }()

    go func() {
        defer wg.Done()
        defer dtlscancel()
        buf := make([]byte, 1600)
        for {
            select {
            case <-dtlsctx.Done():
                return
            default:
            }
            n, err1 := dtlsConn.Read(buf)
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }
            addr1, ok := addr.Load().(net.Addr)
            if !ok {
                log.Printf("Failed: no listener ip")
                return
            }

            _, err1 = listenConn.WriteTo(buf[:n], addr1)
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }
        }
    }()

    wg.Wait()
    listenConn.SetDeadline(time.Time{})
    dtlsConn.SetDeadline(time.Time{})
}

func oneTurnConnection(ctx context.Context, host string, port string, link string, udp bool, realm string, peer net.Addr, conn2 net.PacketConn, c chan<- error) {
    var err error = nil
    defer func() { c <- err }()
    user, pass, url, err1 := getCreds(link)
    if err1 != nil {
        err = fmt.Errorf("failed to get TURN credentials: %s", err1)
        return
    }
var turnServerAddr string
    if host == "" || port == "" {
        
        if len(url) > 5 {
            turnServerAddr = url[5:]
        } else {
            err = fmt.Errorf("invalid TURN url length: '%s'", url)
            return
        }
    } else {
        turnServerAddr = net.JoinHostPort(host, port)
    }
    turnServerUdpAddr, err1 := net.ResolveUDPAddr("udp", turnServerAddr)
    if err1 != nil {
        err = fmt.Errorf("failed to resolve TURN server address: %s", err1)
        return
    }
    turnServerAddr = turnServerUdpAddr.String()
    fmt.Println(turnServerUdpAddr.IP)
    
    var cfg *turn.ClientConfig
    var turnConn net.PacketConn
    var d net.Dialer
    ctx1, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()
    if udp {
        turnConn, err1 = net.ListenPacket("udp4", "") // nolint: noctx
        if err1 != nil {
            err = fmt.Errorf("failed to connect to TURN server: %s", err1)
            return
        }
        defer func() {
            if err1 = turnConn.Close(); err1 != nil {
                err = fmt.Errorf("failed to close TURN server connection: %s", err1)
                return
            }
        }()
    } else {
        conn, err2 := d.DialContext(ctx1, "tcp", turnServerAddr) // nolint: noctx
        if err2 != nil {
            err = fmt.Errorf("failed to connect to TURN server: %s", err2)
            return
        }
        defer func() {
            if err1 = conn.Close(); err1 != nil {
                err = fmt.Errorf("failed to close TURN server connection: %s", err1)
                return
            }
        }()
        turnConn = turn.NewSTUNConn(conn)
    }
    cfg = &turn.ClientConfig{
        STUNServerAddr: turnServerAddr,
        TURNServerAddr: turnServerAddr,
        Conn:           turnConn,
        Username:       user,
        Password:       pass,
        Realm:          realm,
        LoggerFactory:  logging.NewDefaultLoggerFactory(),
    }

    client, err1 := turn.NewClient(cfg)
    if err1 != nil {
        err = fmt.Errorf("failed to create TURN client: %s", err1)
        return
    }
    defer client.Close()

    err1 = client.Listen()
    if err1 != nil {
        err = fmt.Errorf("failed to listen: %s", err1)
        return
    }

    relayConn, err1 := client.Allocate()
    if err1 != nil {
        err = fmt.Errorf("failed to allocate: %s", err1)
        return
    }
    defer func() {
        if err1 := relayConn.Close(); err1 != nil {
            err = fmt.Errorf("failed to close TURN allocated connection: %s", err1)
        }
    }()

    log.Printf("relayed-address=%s", relayConn.LocalAddr().String())

    wg := sync.WaitGroup{}
    wg.Add(2)
    turnctx, turncancel := context.WithCancel(context.Background())
    context.AfterFunc(turnctx, func() {
        relayConn.SetDeadline(time.Now())
        conn2.SetDeadline(time.Now())
    })
    
    go func() {
        defer wg.Done()
        defer turncancel()
        buf := make([]byte, 1600)
        for {
            select {
            case <-turnctx.Done():
                return
            default:
            }
            n, _, err1 := conn2.ReadFrom(buf)
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }

            _, err1 = relayConn.WriteTo(buf[:n], peer)
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }
        }
    }()

    go func() {
        defer wg.Done()
        defer turncancel()
        buf := make([]byte, 1600)
        for {
            select {
            case <-turnctx.Done():
                return
            default:
            }
            n, _, err1 := relayConn.ReadFrom(buf)
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }

            _, err1 = conn2.WriteTo(buf[:n], nil)
            if err1 != nil {
                log.Printf("Failed: %s", err1)
                return
            }
        }
    }()

    wg.Wait()
    relayConn.SetDeadline(time.Time{})
    conn2.SetDeadline(time.Time{})
}

//export StartProxy
func StartProxy(cLink *C.char, cPeerAddr *C.char, cLocalAddr *C.char, cN C.int) {
    select { case <-proxyReady: default: }

    link := C.GoString(cLink)
    peerAddrStr := C.GoString(cPeerAddr)
    localAddrStr := C.GoString(cLocalAddr)
    
    host := ""
    port := "19302"
    realm := "call6-7.vkuser.net"
    n := int(cN)
    udp := true

    ctx, cancel := context.WithCancel(context.Background())
    proxyCancel = cancel
    defer cancel()

    peer, err := net.ResolveUDPAddr("udp", peerAddrStr)
    if err != nil {
        log.Printf("Resolve UDP error: %v", err)
        return
    }

    link = link[len(link)-43:]

    listenConn, err := net.ListenPacket("udp", localAddrStr)
    if err != nil {
        log.Printf("Failed to listen: %s", err)
        return
    }
    defer func() {
        if closeErr := listenConn.Close(); closeErr != nil {
            log.Printf("Failed to close local connection: %s", closeErr)
        }
    }()

    okchan := make(chan struct{})
    connchan := make(chan net.PacketConn)

    wg1 := sync.WaitGroup{}
    wg1.Go(func() {
        for {
            c1 := make(chan error)
            go oneDtlsConnection(ctx, peer, listenConn, connchan, okchan, c1)
            if err := <-c1; err != nil {
                log.Printf("%s", err)
            }
            select {
            case <-ctx.Done():
                return
            default:
            }
        }
    })

    t := time.Tick(100 * time.Millisecond)
    wg1.Go(func() {
        for {
            select {
            case <-ctx.Done():
                return
            case conn2 := <-connchan:
                select {
                case <-t:
                    c := make(chan error)
                    go oneTurnConnection(ctx, host, port, link, udp, realm, peer, conn2, c)
                    if err := <-c; err != nil {
                        log.Printf("%s", err)
                    }
                default:
                }
            }
        }
    })

    for i := 0; i < n-1; i++ {
        time.Sleep(50 * time.Millisecond)
        wg1.Go(func() {
            for {
                select {
                case <-ctx.Done():
                    return
                case <-okchan:
                    select {
                    case conn2 := <-connchan:
                        select {
                        case <-t:
                            c2 := make(chan error)
                            go oneTurnConnection(ctx, host, port, link, udp, realm, peer, conn2, c2)
                            if err := <-c2; err != nil {
                                log.Printf("%s", err)
                            }
                        default:
                        }
                    default:
                    }
                }
            }
        })
    }

    log.Printf("Proxy started on %s", localAddrStr)
    wg1.Wait()
}

//export StopProxy
func StopProxy() {
    if proxyCancel != nil {
        proxyCancel()
        proxyCancel = nil
        log.Println("Proxy gracefully stopped")
    }
}
