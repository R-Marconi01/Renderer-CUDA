#include <cuda_runtime.h>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#include <vector>
#include <random>
#include <iostream>
#include <chrono>
#include <sstream>
#include <algorithm> // Required for std::sort

// Circle structure
struct Circle {
    float x, y, radius;
    float r, g, b, a; // Color components
    Circle(float x, float y, float radius, float r, float g, float b, float a)
        : x(x), y(y), radius(radius), r(r), g(g), b(b), a(a) {}
};

// Kernel to render circles in parallel
__global__ void renderCircles(Circle* d_circles, int num_circles, int canvas_width, int canvas_height, unsigned char* d_pixels) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= num_circles) return;

    Circle circle = d_circles[idx];
    int centerX = static_cast<int>(circle.x);
    int centerY = static_cast<int>(circle.y);
    int radius = static_cast<int>(circle.radius);

    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            int x = centerX + dx;
            int y = centerY + dy;
            if (x < 0 || x >= canvas_width || y < 0 || y >= canvas_height) continue;

            if (dx * dx + dy * dy <= radius * radius) {
                int offset = (y * canvas_width + x) * 4;  // 4 for RGBA

                // Get current pixel color (destination)
                unsigned char dest_r = d_pixels[offset];
                unsigned char dest_g = d_pixels[offset + 1];
                unsigned char dest_b = d_pixels[offset + 2];
                unsigned char dest_a = d_pixels[offset + 3];

                // Calculate source color from circle's color and alpha
                unsigned char src_r = static_cast<unsigned char>(circle.r * 255);
                unsigned char src_g = static_cast<unsigned char>(circle.g * 255);
                unsigned char src_b = static_cast<unsigned char>(circle.b * 255);
                unsigned char src_a = static_cast<unsigned char>(circle.a * 255);

                // Perform alpha blending: output = alpha * source + (1 - alpha) * destination
                float alpha = circle.a;  // Assuming circle.a is in [0, 1]

                d_pixels[offset]     = static_cast<unsigned char>(alpha * src_r + (1 - alpha) * dest_r);
                d_pixels[offset + 1] = static_cast<unsigned char>(alpha * src_g + (1 - alpha) * dest_g);
                d_pixels[offset + 2] = static_cast<unsigned char>(alpha * src_b + (1 - alpha) * dest_b);
                d_pixels[offset + 3] = static_cast<unsigned char>(alpha * src_a + (1 - alpha) * dest_a);
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

    // Inizializza il device CUDA
    cudaError_t err;
    err = cudaSetDevice(0);
    if (err != cudaSuccess) {
        std::cerr << "Errore nel settare il device CUDA: " << cudaGetErrorString(err) << std::endl;
        return -1;
    }

    int deviceCount = 0;
    err = cudaGetDeviceCount(&deviceCount);
    if (err != cudaSuccess || deviceCount == 0) {
        std::cerr << "Nessun device CUDA trovato: " << cudaGetErrorString(err) << std::endl;
        return -1;
    }
    std::cout << "Device count: " << deviceCount << std::endl;
    
    // Ottieni il massimo numero di thread per blocco supportato dalla GPU
    int max_threads_per_block;
    err = cudaDeviceGetAttribute(&max_threads_per_block, cudaDevAttrMaxThreadsPerBlock, 0);
    if (err != cudaSuccess) {
        std::cerr << "Errore nel recuperare l'attributo del device: " << cudaGetErrorString(err) << std::endl;
        return -1;
    }
    std::cout << "Max threads per block: " << max_threads_per_block << std::endl;

    // Lista di diverse configurazioni di cerchi da testare
    std::vector<int> num_circles_config = {10, 100, 1000, 10000, 100000, 1000000};

    // Definisci configurazioni comuni per i thread per blocco
    std::vector<int> thread_configs = {256, 512, 1024};

    // Loop attraverso ogni configurazione di cerchi e thread
    for (int num_circles : num_circles_config) {
        // Genera i cerchi per la configurazione corrente
        std::vector<Circle> circles = generateCircles(num_circles, canvas_width, canvas_height);

        for (int threads_per_block : thread_configs) {
            // Salta configurazioni che superano il massimo supportato
            if (threads_per_block > max_threads_per_block)
                continue;

            // Allocazione della memoria sul device
            Circle* d_circles;
            unsigned char* d_pixels;
            cudaMalloc(&d_circles, num_circles * sizeof(Circle));
            cudaMalloc(&d_pixels, canvas_width * canvas_height * 4 * sizeof(unsigned char));
            cudaMemset(d_pixels, 0, canvas_width * canvas_height * 4);

            // Copia i cerchi sulla GPU
            cudaMemcpy(d_circles, circles.data(), num_circles * sizeof(Circle), cudaMemcpyHostToDevice);

            // Calcola il numero di blocchi necessari
            int blocks = (num_circles + threads_per_block - 1) / threads_per_block;

            // Renderizza i cerchi sulla GPU
            auto start_time = std::chrono::high_resolution_clock::now();
            renderCircles<<<blocks, threads_per_block>>>(d_circles, num_circles, canvas_width, canvas_height, d_pixels);
            cudaDeviceSynchronize();
            auto end_time = std::chrono::high_resolution_clock::now();

            // Copia i pixel dal device al host
            std::vector<unsigned char> pixels(canvas_width * canvas_height * 4);
            cudaMemcpy(pixels.data(), d_pixels, canvas_width * canvas_height * 4, cudaMemcpyDeviceToHost);

            // Salva l'immagine con un filename indicante il numero di cerchi e la configurazione di thread
            auto time_taken = std::chrono::duration<double>(end_time - start_time).count();
            std::stringstream filename;
            filename << "output/parallel_true_n_circles_" << num_circles
                     << "_threads_" << threads_per_block
                     << "_" << time_taken << ".png";
            std::cout << "Saving to: " << filename.str() << std::endl;
            stbi_write_png(filename.str().c_str(), canvas_width, canvas_height, 4, pixels.data(), canvas_width * 4);

            // Libera la memoria allocata sul device
            cudaFree(d_circles);
            cudaFree(d_pixels);

            std::cout << "Rendering completed with " << threads_per_block << " threads per block and " 
                      << num_circles << " circles in " << time_taken << " seconds.\n";
        }
    }

    return 0;
}
