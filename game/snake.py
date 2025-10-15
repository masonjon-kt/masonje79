import tkinter as tk
import random

CELL_SIZE = 20

class SnakeGame(tk.Canvas):
    def __init__(self, master, grid_width, grid_height, speed_increase, obstacle_count, bell_enabled):
        super().__init__(master, width=grid_width*CELL_SIZE, height=grid_height*CELL_SIZE, bg="black")
        self.grid_width = grid_width
        self.grid_height = grid_height
        self.snake = [(5, 5), (4, 5), (3, 5)]
        self.direction = "Right"
        self.food = self.place_food()
        self.speed = 100  # Initial speed in ms
        self.speed_increase = speed_increase
        self.obstacle_count = obstacle_count
        self.obstacles = self.place_obstacles()
        self.bell_enabled = bell_enabled
        self.score = 0
        self.high_score = 0
        self.bind_all("<Key>", self.on_key)
        self.game_over = False
        self.after(self.speed, self.game_loop)
        self.draw()
    def place_obstacles(self):
        # Place obstacles randomly, not on snake or food
        obstacles = set()
        while len(obstacles) < self.obstacle_count:
            pos = (random.randint(0, self.grid_width-1), random.randint(0, self.grid_height-1))
            if pos not in self.snake and pos != self.food:
                obstacles.add(pos)
        return list(obstacles)

    def place_food(self):
        while True:
            pos = (random.randint(0, self.grid_width-1), random.randint(0, self.grid_height-1))
            if pos not in self.snake:
                return pos

    def on_key(self, event):
        key = event.keysym
        opposite = {"Up": "Down", "Down": "Up", "Left": "Right", "Right": "Left"}
        if key == "Escape":
            # End game as if game over, and stop movement
            if self.score > self.high_score:
                self.high_score = self.score
            self.game_over = True
            self.draw()  # Update high score display immediately
            self.create_text(self.grid_width*CELL_SIZE//2, self.grid_height*CELL_SIZE//2, text="Game Over", fill="red", font=("Arial", 24))
            if self.bell_enabled.get():
                self.bell()  # Play negative beep sound on game over
            if hasattr(self, 'show_options_on_game_over'):
                self.show_options_on_game_over()
            # Do not call self.after again, so movement stops
            return
        if key in ["Up", "Down", "Left", "Right"]:
            if self.game_over:
                # Reset game state but keep high score
                if hasattr(self, 'hide_options_on_game_restart'):
                    self.hide_options_on_game_restart()
                self.snake = [(5, 5), (4, 5), (3, 5)]
                self.direction = key
                self.food = self.place_food()
                self.speed = 100
                self.obstacles = self.place_obstacles()
                self.score = 0
                self.game_over = False
                self.draw()
                self.after(self.speed, self.game_loop)
                return
            # Prevent reversing into itself
            if len(self.snake) > 1 and key == opposite[self.direction]:
                return
            self.direction = key

    def game_loop(self):
        head_x, head_y = self.snake[0]
        if self.direction == "Up":
            head_y -= 1
        elif self.direction == "Down":
            head_y += 1
        elif self.direction == "Left":
            head_x -= 1
        elif self.direction == "Right":
            head_x += 1
        new_head = (head_x % self.grid_width, head_y % self.grid_height)
        if new_head in self.snake or new_head in self.obstacles:
            if self.score > self.high_score:
                self.high_score = self.score
                self.draw()  # Update high score display immediately
            self.create_text(self.grid_width*CELL_SIZE//2, self.grid_height*CELL_SIZE//2, text="Game Over", fill="red", font=("Arial", 24))
            if self.bell_enabled.get():
                self.bell()  # Play negative beep sound on game over
            self.game_over = True
            if hasattr(self, 'show_options_on_game_over'):
                self.show_options_on_game_over()
            return
        self.snake.insert(0, new_head)
        if new_head == self.food:
            self.food = self.place_food()
            self.score += 1
            if self.bell_enabled.get():
                self.bell()  # Play beep sound when snake eats food
            self.speed = max(10, int(self.speed * (1 - self.speed_increase / 100.0)))  # Move faster, min 10ms
        else:
            self.snake.pop()
        self.draw()
        self.after(self.speed, self.game_loop)

    def draw(self):
        self.delete("all")
        # Draw score and high score
        self.create_text(5, 5, anchor="nw", text=f"Score: {self.score}", fill="white", font=("Arial", 14, "bold"))
        self.create_text(5, 25, anchor="nw", text=f"High Score: {self.high_score}", fill="yellow", font=("Arial", 12, "bold"))
        # Draw obstacles
        for ox, oy in self.obstacles:
            self.create_rectangle(ox*CELL_SIZE, oy*CELL_SIZE, (ox+1)*CELL_SIZE, (oy+1)*CELL_SIZE, fill="gray")
        # Draw snake
        for x, y in self.snake:
            self.create_rectangle(x*CELL_SIZE, y*CELL_SIZE, (x+1)*CELL_SIZE, (y+1)*CELL_SIZE, fill="green")
        fx, fy = self.food
        self.create_oval(fx*CELL_SIZE, fy*CELL_SIZE, (fx+1)*CELL_SIZE, (fy+1)*CELL_SIZE, fill="red")

if __name__ == "__main__":
    root = tk.Tk()
    root.title("Snake Game")

    bell_enabled = tk.BooleanVar(value=True)

    # Frame for input fields
    input_frame = tk.Frame(root)
    input_frame.pack(side=tk.TOP, pady=10)

    bell_checkbox = tk.Checkbutton(input_frame, text="Enable Bell Sound", variable=bell_enabled)
    bell_checkbox.pack(side=tk.LEFT)

    tk.Label(input_frame, text="Width:").pack(side=tk.LEFT)
    width_entry = tk.Entry(input_frame, width=5)
    width_entry.pack(side=tk.LEFT)
    width_entry.insert(0, "20")

    tk.Label(input_frame, text="Height:").pack(side=tk.LEFT)
    height_entry = tk.Entry(input_frame, width=5)
    height_entry.pack(side=tk.LEFT)
    height_entry.insert(0, "20")

    tk.Label(input_frame, text="Speed Increase (%):").pack(side=tk.LEFT)
    speed_var = tk.StringVar(value="1")
    speed_options = ["0", "0.5", "1", "2", "5", "10", "20"]
    speed_menu = tk.OptionMenu(input_frame, speed_var, *speed_options)
    speed_menu.pack(side=tk.LEFT)

    tk.Label(input_frame, text="Obstacles:").pack(side=tk.LEFT)
    obstacle_entry = tk.Entry(input_frame, width=5)
    obstacle_entry.pack(side=tk.LEFT)
    obstacle_entry.insert(0, "2")

    game_canvas = [None]

    def show_options():
        input_frame.pack(side=tk.TOP, pady=10)

    def hide_options():
        input_frame.pack_forget()

    def start_game():
        hide_options()
        if game_canvas[0]:
            game_canvas[0].destroy()
        try:
            grid_width = int(width_entry.get())
            grid_height = int(height_entry.get())
        except ValueError:
            grid_width = 20
            grid_height = 20
        try:
            speed_increase = float(speed_var.get())
        except ValueError:
            speed_increase = 1.0
        try:
            obstacle_count = int(obstacle_entry.get())
        except ValueError:
            obstacle_count = 5
        # Preserve high score between games
        prev_high_score = 0
        if game_canvas[0] and hasattr(game_canvas[0], 'high_score'):
            prev_high_score = game_canvas[0].high_score
        game_canvas[0] = SnakeGame(root, grid_width, grid_height, speed_increase, obstacle_count, bell_enabled)
        game_canvas[0].high_score = prev_high_score
        game_canvas[0].pack()
        # Patch SnakeGame to show options on game over/reset
        def show_options_on_game_over(self):
            show_options()
        def hide_options_on_game_restart(self):
            hide_options()
        game_canvas[0].show_options_on_game_over = show_options_on_game_over.__get__(game_canvas[0], SnakeGame)
        game_canvas[0].hide_options_on_game_restart = hide_options_on_game_restart.__get__(game_canvas[0], SnakeGame)

    start_button = tk.Button(input_frame, text="Start Game", command=start_game)
    start_button.pack(side=tk.LEFT, padx=10)

    # Start with default game
    start_game()
    root.mainloop()