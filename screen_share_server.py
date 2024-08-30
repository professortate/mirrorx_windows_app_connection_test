import socket

def start_server(ip, port):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind((ip, port))
    server_socket.listen(1)
    print(f"Listening on {ip}:{port}")

    conn, addr = server_socket.accept()
    print(f"Connection established with {addr}")

    with open('received_video.h264', 'wb') as video_file:
        while True:
            data = conn.recv(1024)
            if not data:
                break
            video_file.write(data)
    conn.close()
    print("Video received and saved.")

if __name__ == "__main__":
    start_server("0.0.0.0", 5000)  # Replace with your IP and port
