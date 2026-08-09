#include <iostream>

// Returns the greeting without printing it — Cstring back to Julia.
const char* hello_message() {
    return "Hello, World!";
}

// Prints the greeting, returns how many characters it wrote.
int hello_print() {
    const char* msg = hello_message();
    std::cout << msg << std::endl;
    return 13;
}

// Takes arguments from Julia: greets `name`, `times` over.
int hello_to(const char* name, int times) {
    for (int i = 0; i < times; ++i) {
        std::cout << "Hello, " << name << "!" << std::endl;
    }
    return times;
}

int main() {
    std::cout << "Hello, World!" << std::endl;
    return 0;
}
