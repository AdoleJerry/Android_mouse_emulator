package main

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/go-vgo/robotgo"
	"github.com/gorilla/websocket"
)

type EventMessage struct {
	Type    string  `json:"type"`             // "move", "click", "scroll", "longpress"
	DX      float64 `json:"dx,omitempty"`     // relative X movement
	DY      float64 `json:"dy,omitempty"`     // relative Y movement
	Button  string  `json:"button,omitempty"` // "left", "right"
	ScrollX float64 `json:"scrollX,omitempty"`
	ScrollY float64 `json:"scrollY,omitempty"`
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		// Allow all origins for simplicity (adjust for production)
		return true
	},
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}
	defer conn.Close()
	log.Println("Client connected")

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Println("Read error:", err)
			break
		}

		var event EventMessage
		if err := json.Unmarshal(message, &event); err != nil {
			log.Println("Invalid JSON:", err)
			continue
		}

		switch event.Type {
		case "move":
			x, y := robotgo.GetMousePos()
			robotgo.Move(x+int(event.DX), y+int(event.DY))

		case "click":
			// Click(button string, double bool)
			switch event.Button {
			case "left":
				robotgo.Click("left", false)
			case "right":
				robotgo.Click("right", false)
			}

		case "scroll":
			// Scroll(x, y int, args ...int)
			// x > 0 scrolls right, x < 0 scrolls left
			// y > 0 scrolls up,    y < 0 scrolls down
			// The mobile client usually sends scrollY as:
			//   positive = content moves up (i.e. user wants to go DOWN the page)
			// so we invert here. Adjust the sign to match your client's convention.
			sx := int(event.ScrollX)
			sy := -int(event.ScrollY)
			if sx != 0 || sy != 0 {
				robotgo.Scroll(sx, sy)
			}

		case "longpress":
			robotgo.Click("right", false)

		case "mousedown":
			// Press and hold the specified button without releasing.
			robotgo.MouseDown(event.Button)

		case "mouseup":
			// Release the held button.
			robotgo.MouseUp(event.Button)
		}
	}
}

func main() {
	http.HandleFunc("/ws", handleWebSocket)
	port := ":8080"
	log.Printf("Server listening on %s", port)
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
	// 192.168.1.15 my current pc ip address
}
