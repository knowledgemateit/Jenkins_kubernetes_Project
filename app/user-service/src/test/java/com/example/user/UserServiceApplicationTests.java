package com.example.user;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class UserServiceApplicationTests {

    @Autowired
    private UserRepository repository;

    @Test
    void contextLoads() {
        assertNotNull(repository);
    }

    @Test
    void seederPopulatesUsers() {
        assertTrue(repository.count() >= 2, "Expected at least 2 seeded users");
    }
}
