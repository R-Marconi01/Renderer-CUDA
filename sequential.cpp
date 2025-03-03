#include <iostream>
#include <vector>
#include <random>
#include <chrono>
#include <sstream>
#include <algorithm> // Required for std::sort
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

// Circle structure
struct Circle {
    float x, y, radius;
    float r, g, b, a; // Color components
    Circle(float x, float y, float radius, float r, float g, float b, float a)
        : x(x), y(y), radius(radius), r(r), g(g), b(b), a(a) {}
};

// Function to render circles sequentially
void renderCirclesSequential(std::vector<Circle>& circles, int num_circles, int canvas_width, int canvas_height, unsigned char* pixels) {
    // Initialize the canvas to black (RGBA: 0, 0, 0, 0)
    std::fill(pixels, pixels + (canvas_width * canvas_height * 4), 0);

    // Loop through all circles
    for (int i = 0; i < num_circles; ++i) {
        Circle circle = circles[i];
        int centerX = static_cast<int>(circle.x);
        int centerY = static_cast<int>(circle.y);
        int radius = static_cast<int>(circle.radius);

        // Loop through a square bounding box of the circle's radius
        for (int dy = -radius; dy <= radius; ++dy) {
            for (int dx = -radius; dx <= radius; ++dx) {
                int x = centerX + dx;
                int y = centerY + dy;

                // Skip pixels out of bounds
                if (x < 0 || x >= canvas_width || y < 0 || y >= canvas_height) continue;

                // Check if the pixel is inside the circle (using the equation of a circle)
                if (dx * dx + dy * dy <= radius * radius) {
                    int offset = (y * canvas_width + x) * 4;  // 4 for RGBA

                    // Get current pixel color (destination color)
                    unsigned char dest_r = pixels[offset];
                    unsigned char dest_g = pixels[offset + 1];
                    unsigned char dest_b = pixels[offset + 2];
                    unsigned char dest_a = pixels[offset + 3];

                    // Calculate source color from circle's color and alpha
                    unsigned char src_r = static_cast<unsigned char>(circle.r * 255);
                    unsigned char src_g = static_cast<unsigned char>(circle.g * 255);
                    unsigned char src_b = static_cast<unsigned char>(circle.b * 255);
                    unsigned char src_a = static_cast<unsigned char>(circle.a * 255);

                    // Perform alpha blending: output = alpha * source + (1 - alpha) * destination
                    float alpha = circle.a;  // Assuming circle.a is in [0, 1]

                    pixels[offset] = static_cast<unsigned char>(alpha * src_r + (1 - alpha) * dest_r);
                    pixels[offset + 1] = static_cast<unsigned char>(alpha * src_g + (1 - alpha) * dest_g);
                    pixels[offset + 2] = static_cast<unsigned char>(alpha * src_b + (1 - alpha) * dest_b);
                    pixels[offset + 3] = static_cast<unsigned char>(alpha * src_a + (1 - alpha) * dest_a);
                }
            }
        }
    }
}

// Generate random circles on CPU
std::vector<Circle> generateCircles(int num_circles, int width, int height) {
    std::vector<Circle> circles;
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution<> dis_radius(5, 50);
    std::uniform_real_distribution<> dis_x(0, width);
    std::uniform_real_distribution<> dis_y(0, height);
    std::uniform_real_distribution<> dis_color(0.0f, 1.0f);

    for (int i = 0; i < num_circles; ++i) {
        circles.emplace_back(Circle{
            static_cast<float>(dis_x(gen)),
            static_cast<float>(dis_y(gen)),
            static_cast<float>(dis_radius(gen)),
            static_cast<float>(dis_color(gen)),
            static_cast<float>(dis_color(gen)),
            static_cast<float>(dis_color(gen)),
            static_cast<float>(dis_color(gen)),
        });
    }



    return circles;
}

int main() {
    const int canvas_width = 800;
    const int canvas_height = 600;
    const std::vector<int> num_circles_config = {10, 100, 1000, 10000, 100000, 1000000};

    // Loop through each number of circles configuration
    for (int num_circles : num_circles_config) {
        // Generate circles for the current num_circles configuration
        std::vector<Circle> circles = generateCircles(num_circles, canvas_width, canvas_height);

        // Allocate memory for the pixels
        unsigned char* pixels = new unsigned char[canvas_width * canvas_height * 4];

        // Render circles sequentially
        auto start_time = std::chrono::high_resolution_clock::now();
        renderCirclesSequential(circles, num_circles, canvas_width, canvas_height, pixels);
        auto end_time = std::chrono::high_resolution_clock::now();

        // Save the image with a filename indicating the number of circles
        auto time_taken = std::chrono::duration<double>(end_time - start_time).count();
        std::stringstream filename;
        filename << "soutput/sequential_true_n_circles_" << num_circles
                 << "_" << time_taken << ".png";
        std::cout << "Saving to: " << filename.str() << std::endl;
        stbi_write_png(filename.str().c_str(), canvas_width, canvas_height, 4, pixels, canvas_width * 4);

        // Clean up dynamically allocated memory
        delete[] pixels;

        std::cout << "Rendering completed for " << num_circles << " circles in " << time_taken << " seconds.\n";
    }

    return 0;
}
