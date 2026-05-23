package com.example.user;

import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class DataSeeder {

    @Bean
    CommandLineRunner seed(UserRepository repository) {
        return args -> {
            if (repository.count() == 0) {
                repository.save(new User("Alice", "alice@example.com"));
                repository.save(new User("Bob",   "bob@example.com"));
            }
        };
    }
}
